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
    
    # 0. 移除知乎特有的无意义标签或样式，防止 markdownify 误判
    # 移除开头的标题（如果它与我们要显示的标题重复）
    # 或者将所有的 h1, h2 转为 h3/h4，以防止段落太大
    for h in soup.find_all(['h1', 'h2']):
        # 将 h1/h2 降级，防止在前端显示过大
        h.name = 'h3'

    # 处理可能被误认为标题的加粗段落 (如摘要)
    first_p = soup.find('p')
    if first_p:
        first_b = first_p.find('b', recursive=False) or first_p.find('strong', recursive=False)
        if first_b and len(first_p.get_text(strip=True)) < 100:
            # 如果段落很短且全是加粗，且是第一段，移除加粗以防止 markdownify 误判为 Header
            # 实际上 markdownify 不会因为加粗就变 Header，除非它被误判为 setext header
            pass

    # 1. 处理 LaTeX 公式
    # 查找所有 class 为 ztext-math 的 img 标签，或者 src 包含 zhihu.com/equation 的 img
    for img in soup.find_all('img'):
        src = img.get('src') or ""
        is_equation = "zhihu.com/equation" in src or "eeimg.com/tex" in src or "ztext-math" in (img.get('class') or [])
        
        if is_equation:
            # 尝试从 data-formula 获取 tex (较新版)，或者从 src 的 tex 参数获取
            tex = img.get('data-formula')
            if not tex and 'tex=' in src:
                try:
                    tex = unquote(src.split('tex=')[1].split('&')[0])
                except:
                    pass
            
            if not tex:
                alt = img.get('alt', '')
                if alt and len(alt) > 0 and not alt.startswith('Look'):
                     tex = alt

            if tex:
                # 替换为 LaTeX 代码块
                # 使用 $$ 为块级， $ 为行内。但为了前端统一处理，暂时还是用 ```latex
                # 如果 img 在 p 标签中且是唯一内容，认为是块级
                parent = img.parent
                is_block = parent.name == 'p' and len(parent.find_all(recursive=False)) == 1
                
                if is_block:
                    new_string = f"\n\n```latex\n{tex}\n```\n\n"
                else:
                    new_string = f" $ {tex} $ "
                
                img.replace_with(new_string)
                continue

    # 2. 处理图片 (使用高清图)
    for img in soup.find_all('img'):
        actual_src = img.get('data-original') or img.get('data-actualsrc') or img.get('src')
        if actual_src:
            img['src'] = actual_src
    
    # 3. 处理代码块
    # 知乎的代码块通常在 <div class="highlight"><pre><code>...
    for div in soup.find_all('div', class_='highlight'):
        code_tag = div.find('code')
        if code_tag:
            lang = ""
            for cls in code_tag.get('class', []):
                if cls.startswith('language-'):
                    lang = cls.replace('language-', '')
                    break
            code_content = code_tag.get_text()
            new_pre = soup.new_tag('pre')
            new_code = soup.new_tag('code')
            if lang:
                new_code['class'] = f'language-{lang}'
            new_code.string = code_content
            new_pre.append(new_code)
            div.replace_with(new_pre)

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
