import os
import re
import time
import tarfile
import tempfile
import shutil
from deep_translator import GoogleTranslator

# --- 配置 ---
translator = GoogleTranslator(source='auto', target='en')
SLEEP_TIME = 0.5 
TOTAL_MODIFIED = 0

def do_translate(text):
    if not text or not text.strip():
        return text
    # 排除纯符号、数字、IP、URL、以及常见的代码关键字
    if re.match(r'^[\W\d]+$', text) or '/opt/' in text or 'http' in text:
        return text
    if text.strip() in ['true', 'false', 'null', 'undefined', 'var', 'let', 'const']:
        return text
    
    try:
        res = translator.translate(text)
        time.sleep(SLEEP_TIME)
        # 日志截断
        print(f"      [Trans] {text[:25]}... -> {res[:25]}...")
        return res
    except Exception as e:
        print(f"      [Error] {e}")
        return text

def read_file_content(file_path):
    encodings = ['utf-8', 'windows-1251', 'cp1251', 'latin1']
    for enc in encodings:
        try:
            with open(file_path, 'r', encoding=enc) as f:
                content = f.readlines()
            return content, enc
        except UnicodeDecodeError:
            continue
    return None, None

def has_cyrillic(text):
    return bool(re.search(r'[а-яА-Я]', text))

# --- 1. HTML 处理逻辑 (增强版) ---
def process_html_lines(lines, modified_flag):
    new_lines = []
    # 匹配 >内容<
    tag_text_pattern = re.compile(r'(>)([^<]+?)(<)')
    # 匹配常见 UI 属性 (增加 data-*, aria-*)
    attr_names = r'title|alt|placeholder|value|label|content|data-title|data-tooltip|data-content|aria-label'
    attr_pattern = re.compile(r'\b(' + attr_names + r')=([\"\'])(.*?)([\"\'])')
    # 匹配注释
    comment_pattern = re.compile(r'(<!--\s*)(.*?)(\s*-->)')

    for line in lines:
        # A. 标签内容
        def replace_tag(match):
            p, c, s = match.groups()
            if has_cyrillic(c):
                modified_flag[0] = True
                return f"{p}{do_translate(c)}{s}"
            return match.group(0)
        line = tag_text_pattern.sub(replace_tag, line)

        # B. 属性内容
        def replace_attr(match):
            k, q1, c, q2 = match.groups()
            if has_cyrillic(c):
                modified_flag[0] = True
                return f'{k}={q1}{do_translate(c)}{q2}'
            return match.group(0)
        line = attr_pattern.sub(replace_attr, line)

        # C. 注释
        def replace_comment(match):
            p, c, s = match.groups()
            if has_cyrillic(c):
                modified_flag[0] = True
                return f"{p}{do_translate(c)}{s}"
            return match.group(0)
        line = comment_pattern.sub(replace_comment, line)
        
        new_lines.append(line)
    return new_lines

# --- 2. Markdown 处理逻辑 ---
def process_md_lines(lines, modified_flag):
    new_lines = []
    in_code_block = False

    for line in lines:
        stripped = line.strip()
        if stripped.startswith('```'):
            in_code_block = not in_code_block
            new_lines.append(line)
            continue
        
        if in_code_block or not stripped or stripped.startswith('<'):
            new_lines.append(line)
            continue
            
        if has_cyrillic(line):
            prefix_match = re.match(r'^(\s*(?:#+|\-|\*|\d+\.|>)\s+)?(.*)', line)
            if prefix_match:
                prefix, content = prefix_match.groups()
                if prefix is None: prefix = ""
                translated = do_translate(content)
                new_lines.append(f"{prefix}{translated}\n")
                modified_flag[0] = True
                continue
        new_lines.append(line)
    return new_lines

# --- 3. 脚本/代码/JS 处理逻辑 ---
def process_script_lines(lines, modified_flag):
    new_lines = []
    # 匹配引号字符串 (单双引号)
    string_pattern = re.compile(r'(["\'])(.*?)(["\'])')
    # 匹配注释 (支持 # 和 //)
    comment_pattern = re.compile(r'^(.*?)(#\s*|//\s*)(.*)$')

    for line in lines:
        if line.strip().startswith("#!"):
            new_lines.append(line)
            continue

        # A. 注释
        match_comment = comment_pattern.match(line)
        if match_comment:
            pre, mark, content = match_comment.groups()
            if has_cyrillic(content):
                modified_flag[0] = True
                line = f"{pre}{mark}{do_translate(content)}\n"
        
        # B. 字符串
        def replace_str(match):
            q1, c, q2 = match.groups()
            # JS 中要小心，不要翻译代码逻辑关键字，只翻译包含俄语的内容
            if has_cyrillic(c) and '`' not in c:
                modified_flag[0] = True
                return f"{q1}{do_translate(c)}{q2}"
            return match.group(0)

        line = string_pattern.sub(replace_str, line)
        new_lines.append(line)
    return new_lines

# --- 主文件处理 ---
def process_single_file(file_path, inside_tar=False):
    global TOTAL_MODIFIED
    prefix_log = "    " if inside_tar else ""
    
    filename = os.path.basename(file_path)
    ext = os.path.splitext(file_path)[1].lower()
    
    # === 关键修改：增加 js, css, jsx 等支持 ===
    script_exts = ['.sh', '.cfg', '.conf', '.list', '.txt', '.json', '.xml', '.lua', '.js', '.css', '.jsx', '.ts']
    html_exts = ['.html', '.htm', '.asp', '.php'] # php 也常包含 html
    md_exts = ['.md', '.markdown']
    valid_names = ['config', 'Makefile', 'control', 'postinst', 'prerm']
    
    is_script = any(file_path.endswith(e) for e in script_exts) or filename in valid_names
    is_html = ext in html_exts
    is_md = ext in md_exts

    if not (is_script or is_html or is_md):
        return False

    # 只有压缩包里的文件才打印详细 Log，防止刷屏
    if inside_tar:
        print(f"{prefix_log}Checking: {filename}")
        
    lines, encoding = read_file_content(file_path)
    if not lines: return False

    modified_flag = [False]
    new_lines = []

    if is_html:
        new_lines = process_html_lines(lines, modified_flag)
    elif is_md:
        new_lines = process_md_lines(lines, modified_flag)
    else:
        new_lines = process_script_lines(lines, modified_flag)

    if modified_flag[0]:
        print(f"{prefix_log}-> Modified: {filename}")
        with open(file_path, 'w', encoding=encoding) as f:
            f.writelines(new_lines)
        TOTAL_MODIFIED += 1
        return True
    return False

# --- Tar 处理 ---
def process_tar_file(file_path):
    print(f"📦 Found Archive: {file_path}")
    temp_dir = tempfile.mkdtemp()
    modified_in_tar = False
    try:
        with tarfile.open(file_path, 'r') as tar:
            # 忽略所有权/权限错误
            def no_owners(members):
                for member in members:
                    member.uid = 0
                    member.gid = 0
                    member.uname = ""
                    member.gname = ""
                    yield member
            tar.extractall(path=temp_dir, members=no_owners(tar))
            
        print(f"  -> Extracted. Scanning internal files...")
        
        # 递归遍历解压后的所有目录
        for root, dirs, files in os.walk(temp_dir):
            for file in files:
                inner_path = os.path.join(root, file)
                if process_single_file(inner_path, inside_tar=True):
                    modified_in_tar = True

        if modified_in_tar:
            print(f"  -> Repacking: {file_path}")
            mode = 'w:gz' if file_path.endswith('.gz') or file_path.endswith('.tgz') else 'w'
            with tarfile.open(file_path, mode) as tar:
                tar.add(temp_dir, arcname="")
        else:
            print(f"  -> No changes inside archive.")
    except Exception as e:
        print(f"  [Error tar] {e}")
    finally:
        shutil.rmtree(temp_dir)

def main():
    exclude_dirs = ['.git', '.github']
    for root, dirs, files in os.walk("."):
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        for file in files:
            file_path = os.path.join(root, file)
            # 优先处理压缩包
            if file.endswith(('.tar', '.tar.gz', '.tgz')):
                process_tar_file(file_path)
            else:
                process_single_file(file_path)
    print(f"\n✅ All Done. Total files modified: {TOTAL_MODIFIED}")

if __name__ == "__main__":
    main()
