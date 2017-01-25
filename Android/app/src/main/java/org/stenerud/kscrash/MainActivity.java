package org.stenerud.kscrash;

import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;

import org.json.JSONObject;

import java.io.IOException;
import java.net.URL;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;

public class MainActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        try {
            KSCrashInstallation installation = new KSCrashInstallationStandard(this, new URL("http://10.0.2.2:5000/crashreport"));
//            KSCrashInstallation installation = new KSCrashInstallationEmail(this, "nobody@nowhere.com");
            installation.install();
            installation.sendOutstandingReports();
        } catch (IOException e) {
            e.printStackTrace();
        }

        final Button javaButton = (Button) findViewById(R.id.button_java);
        javaButton.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                throw new IllegalArgumentException("Argument was illegal or something");
//                sendFakeReports();
            }
        });

        final Button nativeButton = (Button) findViewById(R.id.button_native);
        nativeButton.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                causeNativeCrash();
            }
        });

        final Button cppButton = (Button) findViewById(R.id.button_cpp);
        cppButton.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                causeCPPException();
            }
        });

        // Example of a call to a native method
        TextView tv = (TextView) findViewById(R.id.sample_text);
        String result = stringFromTimestamp(0);
        tv.setText(result);
    }

    /**
     * A native method that is implemented by the 'native-lib' native library,
     * which is packaged with this application.
     */
    public native String stringFromTimestamp(long timestamp);
    private native void causeNativeCrash();
    private native void causeCPPException();

    private void sendFakeReports() {
        try {
            List reports = new LinkedList();
            Map report = new HashMap();
            report.put("test", "a value");
            reports.add(new JSONObject(report));
            URL url = new URL("http://10.0.2.2:5000/crashreport");
            KSCrashInstallation installation = new KSCrashInstallationStandard(this, url);
            installation.sendOutstandingReports(reports, new KSCrashReportFilter.CompletionCallback() {
                @Override
                public void onCompletion(List reports) throws KSCrashReportFilteringFailedException {
                    Log.i("MainActivity", "Sent " + reports.size() + " reports");
                }
            });
        } catch(Exception e) {
            Log.e("MainActivity", "Error sending fake reports", e);
        }
    }
}
