package com.leohub.smartexpensetracker;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.provider.Telephony;
import android.telephony.SmsMessage;
import android.util.Log;

import androidx.core.app.NotificationCompat;
import androidx.core.app.NotificationManagerCompat;

import org.json.JSONArray;
import org.json.JSONObject;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Captures incoming rent-payment SMS even when the Flutter app is closed.
 *
 * On a match it (1) posts a notification and (2) appends the parsed record to
 * SharedPreferences. The Flutter side drains these via the "rent_capture"
 * MethodChannel and merges them into the Hive ledger.
 *
 * The regexes here MIRROR lib/services/rent_sms_parser.dart — keep both in
 * sync if the DTB SMS format changes.
 */
public class SmsReceiver extends BroadcastReceiver {
    private static final String TAG = "RentSmsReceiver";

    static final String PREFS = "rent_capture";
    static final String KEY_PENDING = "pending";
    private static final String CHANNEL_ID = "rent_payments";

    private static final Pattern P_HOLDER =
            Pattern.compile("Dear\\s+(.+?)\\s*,", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_AMOUNT =
            Pattern.compile("received\\s+(?:KES|KSH|of\\s+)?\\s*([\\d,]+(?:\\.\\d{1,2})?)", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_ACCOUNT =
            Pattern.compile("into\\s+(\\S+)\\s+from", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_FROM_PHONE =
            Pattern.compile("from\\s+([A-Za-z][A-Za-z .'\\-]+?)\\s+(\\d{9,15})", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_FROM_NOPHONE =
            Pattern.compile("from\\s+([A-Za-z][A-Za-z .'\\-]+?)\\s+(?=on\\b|ref\\b|mpesa\\b|acc\\b|account\\b|new\\b|\\.)", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_REF =
            Pattern.compile("(?<!Mpesa\\s)Ref:\\s*([A-Za-z0-9]+)", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_MPESA_REF =
            Pattern.compile("Mpesa\\s*Ref:\\s*([A-Za-z0-9]+)", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_CONFIRMED =
            Pattern.compile("\\b([A-Z0-9]{10})\\b\\s+Confirmed", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_DATE =
            Pattern.compile("on\\s+(\\d{1,2})/(\\d{1,2})/(\\d{2,4})", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_TIME =
            Pattern.compile("at\\s+(\\d{1,2})[.:](\\d{2})\\s*(AM|PM)", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_BANK =
            Pattern.compile("\\.\\s*([A-Za-z]{2,6})\\s*$");
    private static final Pattern P_OUTGOING =
            Pattern.compile("\\b(you have sent|sent to|paid to|pay bill|withdraw|debited|otp|password|pin|verification)\\b", Pattern.CASE_INSENSITIVE);
    private static final Pattern P_MPESA_TAG =
            Pattern.compile("m-?pesa", Pattern.CASE_INSENSITIVE);

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!Telephony.Sms.Intents.SMS_RECEIVED_ACTION.equals(intent.getAction())) {
            return;
        }
        SmsMessage[] messages = Telephony.Sms.Intents.getMessagesFromIntent(intent);
        if (messages == null || messages.length == 0) return;

        // Concatenate multipart SMS into one body.
        StringBuilder sb = new StringBuilder();
        for (SmsMessage m : messages) {
            if (m != null && m.getMessageBody() != null) sb.append(m.getMessageBody());
        }
        String body = sb.toString();
        if (body.isEmpty()) return;

        JSONObject record = parse(body);
        if (record == null) {
            Log.d(TAG, "SMS is not an inbound payment; ignoring.");
            return;
        }
        if (!matchesKeyword(context, body)) {
            Log.d(TAG, "Payment does not contain a configured business keyword; ignoring.");
            return;
        }

        try {
            persist(context, record);
            notifyUser(context, record);
        } catch (Exception e) {
            Log.e(TAG, "Failed to handle rent SMS", e);
        }
    }

    /** Returns a JSON record matching RentPayment.fromJson, or null if not an inbound payment. */
    static JSONObject parse(String body) {
        if (body == null || body.isEmpty()) return null;
        if (!body.toLowerCase().contains("received")) return null;
        if (P_OUTGOING.matcher(body).find()) return null;

        Matcher amount = P_AMOUNT.matcher(body);
        if (!amount.find()) return null;
        double amt;
        try {
            amt = Double.parseDouble(amount.group(1).replace(",", ""));
        } catch (NumberFormatException e) {
            return null;
        }
        if (amt <= 0) return null;

        // Payer name (required) + optional phone.
        String tenant;
        String phone = "";
        Matcher fromPhone = P_FROM_PHONE.matcher(body);
        if (fromPhone.find()) {
            tenant = fromPhone.group(1).trim();
            phone = fromPhone.group(2).trim();
        } else {
            Matcher fromNoPhone = P_FROM_NOPHONE.matcher(body);
            if (!fromNoPhone.find()) return null;
            tenant = fromNoPhone.group(1).trim();
        }

        // M-Pesa ref: explicit "Mpesa Ref:" or leading "CODE Confirmed".
        String mpesaRef = group(P_MPESA_REF, body);
        if (mpesaRef.isEmpty()) mpesaRef = group(P_CONFIRMED, body);

        // Bank/channel: trailing tag, else "M-PESA" if it looks like an M-Pesa msg.
        String bank = group(P_BANK, body);
        if (bank.isEmpty() && P_MPESA_TAG.matcher(body).find()) bank = "M-PESA";

        long paidAtMillis = composeDateTime(body);

        try {
            JSONObject o = new JSONObject();
            o.put("holder", group(P_HOLDER, body));
            o.put("tenantName", tenant);
            o.put("phone", phone);
            o.put("amount", amt);
            o.put("paidIntoAccount", group(P_ACCOUNT, body));
            o.put("ref", group(P_REF, body));
            o.put("mpesaRef", mpesaRef);
            o.put("bank", bank);
            o.put("paidAt", paidAtMillis); // epoch millis; Dart side tolerates int
            o.put("rawSms", body.trim());
            return o;
        } catch (Exception e) {
            return null;
        }
    }

    /** True if the SMS body contains any configured business keyword. */
    private boolean matchesKeyword(Context context, String body) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        java.util.Set<String> keywords =
                prefs.getStringSet("match_keywords", java.util.Collections.emptySet());
        if (keywords.isEmpty()) return false;
        String normBody = normalize(body);
        for (String k : keywords) {
            if (!k.isEmpty() && normBody.contains(k)) return true;
        }
        return false;
    }

    /** Lowercased, whitespace-stripped, matching Business.normalize in Dart. */
    private static String normalize(String raw) {
        return raw.toLowerCase().replaceAll("\\s+", "");
    }

    private static String group(Pattern p, String body) {
        Matcher m = p.matcher(body);
        return m.find() ? m.group(1).trim() : "";
    }

    private static long composeDateTime(String body) {
        Matcher d = P_DATE.matcher(body);
        if (!d.find()) return System.currentTimeMillis();
        int day = Integer.parseInt(d.group(1));
        int month = Integer.parseInt(d.group(2));
        int year = Integer.parseInt(d.group(3));
        if (year < 100) year += 2000;

        int hour = 0, minute = 0;
        Matcher t = P_TIME.matcher(body);
        if (t.find()) {
            hour = Integer.parseInt(t.group(1));
            minute = Integer.parseInt(t.group(2));
            String mer = t.group(3).toUpperCase();
            if (mer.equals("PM") && hour != 12) hour += 12;
            if (mer.equals("AM") && hour == 12) hour = 0;
        }
        java.util.Calendar c = java.util.Calendar.getInstance();
        c.clear();
        c.set(year, month - 1, day, hour, minute, 0);
        return c.getTimeInMillis();
    }

    private void persist(Context context, JSONObject record) throws Exception {
        SharedPreferences prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        String existing = prefs.getString(KEY_PENDING, "[]");
        JSONArray arr;
        try {
            arr = new JSONArray(existing);
        } catch (Exception e) {
            arr = new JSONArray();
        }
        // Avoid duplicate pending entries with the same Mpesa ref.
        String ref = record.optString("mpesaRef", "");
        if (!ref.isEmpty()) {
            for (int i = 0; i < arr.length(); i++) {
                if (ref.equals(arr.getJSONObject(i).optString("mpesaRef", ""))) {
                    return; // already pending
                }
            }
        }
        arr.put(record);
        prefs.edit().putString(KEY_PENDING, arr.toString()).apply();
        Log.d(TAG, "Persisted rent record; pending=" + arr.length());
    }

    private void notifyUser(Context context, JSONObject record) {
        createChannel(context);

        String payer = record.optString("tenantName", "");
        double amount = record.optDouble("amount", 0);
        String ref = record.optString("ref", "");
        String title = "Payment received";
        String text = String.format(java.util.Locale.getDefault(),
                "%s — KES %,.2f%s", payer.isEmpty() ? "Payment" : payer, amount,
                ref.isEmpty() ? "" : " (Ref " + ref + ")");

        Intent launch = context.getPackageManager()
                .getLaunchIntentForPackage(context.getPackageName());
        PendingIntent pi = null;
        if (launch != null) {
            int flags = PendingIntent.FLAG_UPDATE_CURRENT;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                flags |= PendingIntent.FLAG_IMMUTABLE;
            }
            pi = PendingIntent.getActivity(context, 0, launch, flags);
        }

        NotificationCompat.Builder b = new NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(android.R.drawable.stat_notify_chat)
                .setContentTitle(title)
                .setContentText(text)
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH);
        if (pi != null) b.setContentIntent(pi);

        try {
            NotificationManagerCompat.from(context)
                    .notify((int) (System.currentTimeMillis() & 0x7FFFFFFF), b.build());
        } catch (SecurityException e) {
            // POST_NOTIFICATIONS not granted (Android 13+); record is still persisted.
            Log.w(TAG, "Notification permission missing", e);
        }
    }

    private void createChannel(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID, "Rent payments", NotificationManager.IMPORTANCE_HIGH);
            channel.setDescription("Alerts when a rent payment SMS is received");
            NotificationManager nm = context.getSystemService(NotificationManager.class);
            if (nm != null) nm.createNotificationChannel(channel);
        }
    }
}
