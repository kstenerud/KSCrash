package org.stenerud.kscrash;

import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;

import java.io.IOException;

public class MainActivity extends AppCompatActivity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        try {
            KSCrash.getInstance().install(getApplicationContext());
        } catch (IOException e) {
            e.printStackTrace();
        }

        final Button javaButton = (Button) findViewById(R.id.button_java);
        javaButton.setOnClickListener(new View.OnClickListener() {
            public void onClick(View v) {
                throw new IllegalArgumentException("Argument was illegal or something");
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
}
