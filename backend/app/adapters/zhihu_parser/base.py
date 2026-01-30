import json
import html
from typing import Optional, Dict, Any, List
from bs4 import BeautifulSoup
import re


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


def _process_latex_formulas(soup: BeautifulSoup) -> None:
    """
    处理知乎 LaTeX 公式，将 <img eeimg="1"> 转换为 Markdown 格式
    
    知乎公式格式:
    <img src="https://www.zhihu.com/equation?tex=..." alt="LaTeX源码" eeimg="1"/>
    
    - 块公式: LaTeX 以 \\ 结尾，或 img 是 <p> 的唯一主要内容
    - 行内公式: 与文字混排
    """
    for img in soup.find_all('img', attrs={'eeimg': '1'}):
        latex_raw = img.get('alt', '')
        if not latex_raw:
            continue
        
        latex = html.unescape(latex_raw)
        
        is_block = latex.rstrip().endswith('\\\\')
        
        if not is_block:
            parent = img.parent
            if parent and parent.name == 'p':
                direct_texts = []
                for child in parent.children:
                    if isinstance(child, str):
                        text = child.strip()
                        if text:
                            direct_texts.append(text)
                if not direct_texts:
                    is_block = True
        
        clean_latex = latex.rstrip('\\').rstrip()
        if clean_latex.endswith('\\'):
            clean_latex = clean_latex[:-1]
        
        if is_block:
            replacement = f'\n$$\n{clean_latex}\n$$\n'
        else:
            replacement = f'${clean_latex}$'
        
        new_tag = soup.new_string(replacement)
        img.replace_with(new_tag)


def preprocess_zhihu_html(html_content: str) -> str:
    """预处理知乎 HTML: 处理公式、图片、代码块，移除冗余标题"""
    if not html_content:
        return ""
    
    soup = BeautifulSoup(html_content, 'html.parser')
    
    # 0. 移除知乎内容中可能存在的冗余标题 (通常是 h1, h2)
    for h in soup.find_all(['h1', 'h2', 'h3']):
        if h.name in ['h1', 'h2']:
            h.name = 'h3'

    # 特殊处理：移除开头可能完全重复标题的段落
    first_tags = soup.find_all(recursive=False)[:3]
    for tag in first_tags:
        if tag.name in ['h1', 'h2', 'h3', 'p']:
            if tag.find('b') or tag.find('strong') or tag.name.startswith('h'):
                pass

    # 1. LaTeX 公式处理
    _process_latex_formulas(soup)
    
    # 2. 移除 <noscript> 标签（知乎图片有两份：noscript内一份，外面一份懒加载的）
    for noscript in soup.find_all('noscript'):
        noscript.decompose()

    # 3. 处理图片 (使用高清图，跳过公式图片和SVG占位符)
    for img in soup.find_all('img'):
        src = img.get('src') or ""
        # 跳过公式图片
        if "equation" in src or "tex=" in src:
            continue
        # 跳过SVG占位符
        if src.startswith('data:'):
            src = ""
        actual_src = img.get('data-original') or img.get('data-actualsrc') or src
        if actual_src and actual_src.startswith('http'):
            img['src'] = actual_src
        elif not actual_src:
            # 无有效图片来源，移除这个img标签
            img.decompose()
    
    # 4. 处理代码块
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

def _extract_zhimg_hash(url: str) -> Optional[str]:
    """从知乎图片URL中提取hash值用于去重
    
    例如: https://pic1.zhimg.com/v2-c3f023c96badcf6f634fc246e23f74bd_r.jpg
    提取: v2-c3f023c96badcf6f634fc246e23f74bd
    """
    match = re.search(r'(v2-[a-f0-9]+)', url)
    return match.group(1) if match else None


def extract_images(html_content: str) -> List[str]:
    """提取所有图片 URL，去重并优先保留高清版本"""
    if not html_content:
        return []
    soup = BeautifulSoup(html_content, 'html.parser')
    
    # 用hash去重，保留高清版本（_r.jpg 优先于 _720w.jpg）
    seen_hashes: Dict[str, str] = {}
    
    for img in soup.find_all('img'):
        # Skip equations if any survived
        src = img.get('src') or ""
        if "equation" in src or "tex=" in src:
            continue
        
        # 优先使用高清版本 data-original
        actual_src = img.get('data-original') or img.get('data-actualsrc') or img.get('src')
        if not actual_src or not actual_src.startswith('http'):
            continue
        
        # 跳过SVG占位符
        if actual_src.startswith('data:'):
            continue
            
        # 提取hash用于去重
        img_hash = _extract_zhimg_hash(actual_src)
        if img_hash:
            # 如果已有该hash，优先保留高清版本（_r.jpg）
            if img_hash in seen_hashes:
                existing = seen_hashes[img_hash]
                # 高清版本包含 _r. 而非 _720w 或 /50/
                if '_r.' in actual_src and '_r.' not in existing:
                    seen_hashes[img_hash] = actual_src
            else:
                seen_hashes[img_hash] = actual_src
        else:
            # 非知乎图片，直接添加（用URL本身作为key）
            seen_hashes[actual_src] = actual_src
    
    return list(seen_hashes.values())
