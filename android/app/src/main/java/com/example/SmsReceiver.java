package com.example.smart_expense_tracker;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.os.Bundle;
import android.telephony.SmsMessage;
import android.util.Log;

public class SmsReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Bundle bundle = intent.getExtras();
        if (bundle != null) {
            Object[] pdus = (Object[]) bundle.get("pdus");
            if (pdus != null) {
                for (Object pdu : pdus) {
                    SmsMessage sms = SmsMessage.createFromPdu((byte[]) pdu);
                    String sender = sms.getOriginatingAddress();
                    String messageBody = sms.getMessageBody();

                    Log.d("SMSReceiver", "SMS Received from: " + sender);
                    Log.d("SMSReceiver", "Message: " + messageBody);

                    // TODO: Pass the SMS data to the Flutter app via a platform channel
                }
            }
        }
    }
}
