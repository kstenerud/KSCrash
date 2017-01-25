//
//  Copyright (c) 2017 Karl Stenerud. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall remain in place
// in this source code.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

package org.stenerud.kscrash;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.support.v4.content.FileProvider;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

/**
 * Send files over email.
 *
 * Input: File
 * Output: File
 */
public class KSCrashReportFilterEmail implements KSCrashReportFilter {
    private Context context;
    private List<String> recipients;
    private String subject;
    private String message;

    /**
     * Constructor.
     *
     * @param context A context that can open an email intent.
     * @param recipients A list of recipients for the email.
     * @param subject The subject of the message.
     * @param message An optional message body to send in addition to the attachments.
     */
    public KSCrashReportFilterEmail(Context context, List<String> recipients, String subject, String message) {
        this.context = context;
        this.recipients = recipients;
        this.subject = subject;
        this.message = message;
    }

    @Override
    public void filterReports(List reports, CompletionCallback completionCallback) throws KSCrashReportFilteringFailedException {
        ArrayList<Uri> attachments = new ArrayList<>();
        String authority = BuildConfig.APPLICATION_ID + ".provider";
        for(Object report: reports) {
            attachments.add(FileProvider.getUriForFile(context, authority, (File)report));
        }

        Intent intent = new Intent(Intent.ACTION_SEND_MULTIPLE);
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
        intent.setType("*/*");
        // TODO: Why does this fail?
//        intent.setData(Uri.parse("mailto:"));
        intent.putExtra(Intent.EXTRA_EMAIL, recipients.toArray());
        intent.putExtra(Intent.EXTRA_SUBJECT, subject);
        // Workaround for framework bug
        ArrayList<String> text = new ArrayList<>();
        text.add(message);
        intent.putExtra(Intent.EXTRA_TEXT, text);
        intent.putExtra(Intent.EXTRA_STREAM, attachments);

        if (intent.resolveActivity(context.getPackageManager()) != null) {
            context.startActivity(intent);
        }

        completionCallback.onCompletion(reports);
    }
}
