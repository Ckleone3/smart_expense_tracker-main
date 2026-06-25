package com.leohub.smartexpensetracker

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "rent_capture"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("rent_capture", Context.MODE_PRIVATE)
                when (call.method) {
                    // Returns the JSON array of rent records captured while the
                    // app was closed, then clears the native buffer.
                    "getAndClearPending" -> {
                        val pending = prefs.getString("pending", "[]")
                        prefs.edit().putString("pending", "[]").apply()
                        result.success(pending)
                    }
                    // Stores the businesses' keyword keys so the receiver only
                    // captures payments whose SMS contains a configured keyword.
                    "setLedgerKeywords" -> {
                        val keywords = call.argument<List<String>>("keywords") ?: emptyList()
                        prefs.edit()
                            .putStringSet("match_keywords", keywords.toSet())
                            .apply()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
