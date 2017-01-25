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

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.net.URLConnection;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;

/**
 * Builds an HTTP multipart body, with string and file fields.
 * Call toByteArray() to get the bytes for writing to an HTTP output stream.
 */
public class MultipartPostBody {
    private static final String boundary = UUID.randomUUID().toString().replaceAll("-", "") + ".post.boundary";
    private static final String linefeed = "\r\n";
    private Map<String, String> stringFields = new HashMap<>();
    private Map<String, byte[]> dataFields = new HashMap<>();
    private String charset;

    public static final String contentType = "multipart/form-data; boundary=" + boundary;

    public MultipartPostBody() {
        this("UTF-8");
    }

    public MultipartPostBody(String charset) {
        this.charset = charset;
    }

    public void setStringFields(Map<String, String> fields) {
        this.stringFields = fields;
    }

    public void setField(String name, String value) {
        stringFields.put(name, value);
    }

    public void setDataFields(Map<String, byte[]> fields) {
        this.dataFields = fields;
    }

    public void setField(String name, byte[] value) {
        dataFields.put(name, value);
    }

    public byte[] toByteArray() throws IOException {
        ByteArrayOutputStream outStream = new ByteArrayOutputStream();
        PrintWriter writer = new PrintWriter(new OutputStreamWriter(outStream, charset), true);

        for(String key: stringFields.keySet()) {
            addTextFieldPreamble(writer, key);
            writer.append(stringFields.get(key));
            terminateTextField(writer);
        }

        for(String key: dataFields.keySet()) {
            addDataFieldPreamble(writer, key, key);
            writer.flush();
            outStream.write(dataFields.get(key));
            terminateDataField(writer);
        }

        terminatePayload(writer);
        writer.close();

        return outStream.toByteArray();
    }

    private void terminateTextField(PrintWriter writer) {
        writer.append(linefeed);
    }

    private void terminateDataField(PrintWriter writer) {
        writer.append(linefeed).append(linefeed);
    }

    private void terminatePayload(PrintWriter writer) {
        writer.append(linefeed).append("--").append(boundary).append("--").append(linefeed);
    }

    private void addCommonFieldPreamble(PrintWriter writer, String name) {
        writer.append("--").append(boundary).append(linefeed);
        writer.append("Content-Disposition: form-data; name=\"").append(escaped(name)).append("\"");
    }

    private void addTextFieldPreamble(PrintWriter writer, String name) {
        addCommonFieldPreamble(writer, name);
        writer.append(linefeed);
        writer.append("Content-Type: text/plain; charset=").append(charset).append(linefeed).append(linefeed);
    }

    private void addDataFieldPreamble(PrintWriter writer, String name, String filename) {
        addCommonFieldPreamble(writer, name);
        writer.append("; filename=\"").append(escaped(filename)).append("\"").append(linefeed);
        writer.append("Content-Type: ").append(URLConnection.guessContentTypeFromName(filename)).append(linefeed);
        writer.append("Content-Transfer-Encoding: binary").append(linefeed).append(linefeed);
    }

    private String escaped(String value) {
        return value.replaceAll("\"", "\\\"");
    }
}
