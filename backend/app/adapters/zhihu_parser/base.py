import json
from typing import Optional, Dict, Any, List
from bs4 import BeautifulSoup
import re
from urllib.parse import unquote

def extract_initial_data(html_content: str) -> Optional[Dict[str, Any]]:
    """从 HTML 中提取 js-initialData JSON 数据"""
    soup = BeautifulSoup(html_content, 'html.parser')
    script = soup.find('script', id='js-initialData')
    if script and script.string:
        try:
            return json.loads(script.string)
        except json.JSONDecodeError:
            return None
    return None

def preprocess_zhihu_html(html_content: str) -> str:
    """预处理知乎 HTML: 处理公式、图片、代码块"""
    if not html_content:
        return ""
    
    soup = BeautifulSoup(html_content, 'html.parser')
    
    # 1. 处理 LaTeX 公式
    # 查找所有 class 为 ztext-math 的 img 标签，或者 src 包含 zhihu.com/equation 的 img
    for img in soup.find_all('img'):
        src = img.get('src') or ""
        is_equation = "zhihu.com/equation" in src or "eeimg.com/tex" in src
        
        if is_equation:
            # 尝试从 data-formula 获取 tex (较新版)，或者从 src 的 tex 参数获取
            tex = img.get('data-formula')
            if not tex and 'tex=' in src:
                try:
                    tex = unquote(src.split('tex=')[1])
                except:
                    pass
            
            if not tex:
                alt = img.get('alt', '')
                # 有时候 alt 就是 tex
                if alt and len(alt) > 0 and not alt.startswith('Look'):
                     tex = alt

            if tex:
                # 替换为 LaTeX 代码块，以便前端通过 CodeBuilder 渲染
                # 使用 markdownify 时，pre/code 可能会被处理，所以直接替换为文本格式的 markdown block
                new_string = f"```latex\n{tex}\n```"
                img.replace_with(new_string)
                continue

    # 2. 处理图片 (使用高清图)
    # 这一步主要是为了 markdownify 能拿到正确的 src
    # 同时可以去除公式图片以免被 markdownify 转为 ![alt](url) (如果上面没处理掉)
    for img in soup.find_all('img'):
        actual_src = img.get('data-original') or img.get('data-actualsrc') or img.get('src')
        if actual_src:
            img['src'] = actual_src
    
    # 3. 处理代码块 (Pre-process code blocks if needed, but markdownify usually handles <pre><code>)
    # Zhihu sometimes uses <div class="highlight"><pre><code class="language-text">...
    
    return str(soup)

def extract_images(html_content: str) -> List[str]:
    """提取所有图片 URL"""
    if not html_content:
        return []
    soup = BeautifulSoup(html_content, 'html.parser')
    urls = []
    for img in soup.find_all('img'):
        # Skip equations if any survived
        src = img.get('src') or ""
        if "equation" in src or "tex=" in src:
            continue
            
        actual_src = img.get('data-original') or img.get('data-actualsrc') or img.get('src')
        if actual_src and actual_src.startswith('http'):
            urls.append(actual_src)
    return urls
