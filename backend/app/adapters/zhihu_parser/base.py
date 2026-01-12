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
    """预处理知乎 HTML: 处理公式、图片、代码块，移除冗余标题"""
    if not html_content:
        return ""
    
    soup = BeautifulSoup(html_content, 'html.parser')
    
    # 0. 移除知乎内容中可能存在的冗余标题 (通常是 h1, h2)
    # 很多时候内容开头会重复一次标题
    for h in soup.find_all(['h1', 'h2', 'h3']):
        text = h.get_text(strip=True)
        # 如果标题太长或者包含"如何评价"等关键词且在开头，考虑移除或降级
        # 但为了稳妥，我们主要降级所有 h1, h2 到 h3/h4
        if h.name in ['h1', 'h2']:
            h.name = 'h3'

    # 特殊处理：移除开头可能完全重复标题的段落
    # 这通常在专栏文章或回答开头出现
    first_tags = soup.find_all(recursive=False)[:3]
    for tag in first_tags:
        if tag.name in ['h1', 'h2', 'h3', 'p']:
            text = tag.get_text(strip=True)
            # 如果这个标签的内容只是重复了标题，或者非常像标题且加粗了
            if tag.find('b') or tag.find('strong') or tag.name.startswith('h'):
                # 我们很难在这里拿到真正的 question title，
                # 但知乎回答正文里通常不应该再出现 h1/h2
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
