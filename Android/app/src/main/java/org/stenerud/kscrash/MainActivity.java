package org.stenerud.kscrash;

import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
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

        // Example of a call to a native method
        TextView tv = (TextView) findViewById(R.id.sample_text);
        String result = stringFromTimestamp(0);
//        tv.setText(stringFromJNI());
        tv.setText(result);
    }

    /**
     * A native method that is implemented by the 'native-lib' native library,
     * which is packaged with this application.
     */
    public native String stringFromJNI();
    public native String stringFromTimestamp(long timestamp);
}
