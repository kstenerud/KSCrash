from flask import Flask
from flask import request
import module_locator
import os

def ensure_path_exists(path):
    if not os.path.exists(path):
        os.makedirs(path)

def get_next_post_index(path):
    dirs = [f for f in os.listdir(path) if os.path.isdir(os.path.join(path, f))]
    if len(dirs) == 0:
        return 1
    dirname = max(dirs)
    return int(os.path.basename(os.path.normpath(dirname))) + 1

posts_path = os.path.join(module_locator.module_path(), "posts")
ensure_path_exists(posts_path)
next_post_index = get_next_post_index(posts_path)
print "Next post index: %d" % next_post_index

app = Flask(__name__)

def save_text_fields(fields, filename):
    text_file = open(filename, "w")
    print "Text Fields:"
    for key in fields:
        field_string = "%s: %s" % (key, fields[key])
        print "    %s" % field_string
        text_file.write(field_string)
    text_file.close()

def save_file_fields(fields, path):
    ensure_path_exists(path)
    print "File Fields:"
    for filename in fields:
        data_file = fields[filename]
        save_path = os.path.join(path, filename)
        print "    %s" % filename
        data_file.save(save_path)

def save_post(request, index):
    print "Post #%d" % index
    base_path = os.path.join(posts_path, str(index))
    ensure_path_exists(base_path)
    save_text_fields(request.form, os.path.join(base_path, "text_fields.txt"))
    save_file_fields(request.files, os.path.join(base_path, "file_fields"))

@app.route('/crashreport', methods=['POST'])
def crashreport():
    global next_post_index
    save_post(request, next_post_index)
    next_post_index += 1
    return 'OK'
