import os
import re
import json
import requests
from bs4 import BeautifulSoup
from markdownify import markdownify as md

# 配置信息
HEADERS = {
    "authority": "zhuanlan.zhihu.com",
    "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
    "accept-language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
    "cache-control": "no-cache",
    # 完整 Cookie 字符串
    "cookie": 'SESSIONID=IDDWvDzUHSPk6BvcImtvTih7GPnc7QPi8dnydeQisHf; JOID=UVoRAUzq4ChIUWJnU-v1fefwOt1Nid5cJQVaGzqlix0-LjEQYB9WTyBUZWdQMMloAHfwnByE2kJ6vEzzQNY2mfo=; osd=UlkVBUrp4yxMV2FkV-_zfuT0PttOitpYIwZZHz6jiB46KjcTYxtSSSNXYWNWM8psBHHznxiA3EF5uEj1Q9Uynfw=; _zap=cb4df94b-e7e7-413b-b60b-cc2d360184ab; d_c0=AGDSY59ZvxmPTksc-5vnXwLzkGcKNa5sLcs=|1735118016; _xsrf=LeiQnW9WQH64GsAyz2SaLVuLD3zKH0mq; z_c0=2|1:0|10:1767444716|4:z_c0|92:Mi4xR0VRSU9nQUFBQUFBWU5Kam4xbV9HU1lBQUFCZ0FsVk5qS1pFYWdCRlZJdVhJVnJOaGktbVdWOGlEZVVjT0dvTDhR|4a668ee4f99d78da43f5c53c284cd530fd08097b766596e32f150b26b7522bb7; Hm_lvt_98beee57fd2ef70ccdd5ca52b9740c49=1767520228,1767691497,1767769002,1767778908; __zse_ck=005_As/psuLn7na4nyCstaa7ir0VvU3qHFm4upBRVTqqKFA1T72gjGDr20ciRpT1A2BJYg=n1xqcucPP7ytuEG8TDWkTSHm4lAH8e2EIVrpwvYMYHTMQQb95WJvBehgCXr/2-D1o/WqOb1mE7wzDeePYA5qKQVbY0zOjZWvy6eU1Dbx3pdHkLCVKUcapAXLSSew19IaYnvndHT3QlX8hUnle2WcBJLGeoCuAz4Su1ginJvJpFkxfr7+wmU7kC0niVAus1; BEC=6c53268835aec2199978cd4b4f988f8c', 
    "pragma": "no-cache",
    "sec-ch-ua": '"Google Chrome";v="143", "Chromium";v="143", "Not A(Brand";v="24"',
    "user-agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
}

def download_image(url, save_dir):
    """下载图片并返回本地相对路径"""
    if not url:
        return ""
    try:
        # 移除知乎图片链接后的参数
        clean_url = url.split('?')[0]
        img_name = clean_url.split('/')[-1]
        img_path = os.path.join(save_dir, img_name)
        
        if not os.path.exists(img_path):
            resp = requests.get(url, headers=HEADERS, timeout=10)
            if resp.status_code == 200:
                with open(img_path, 'wb') as f:
                    f.write(resp.content)
        return f"./images/{img_name}"
    except Exception as e:
        print(f"图片下载失败: {url}, 错误: {e}")
        return url

def parse_zhihu_column(url):
    # 1. 获取网页内容
    response = requests.get(url, headers=HEADERS)
    response.encoding = 'utf-8'
    html_content = response.text
    soup = BeautifulSoup(html_content, 'html.parser')

    # 2. 提取数据核心：js-initialData 标签 
    data_script = soup.find('script', id='js-initialData')
    if not data_script:
        print("未能找到文章数据，请检查链接或是否被反爬限制")
        return

    data = json.loads(data_script.string)
    
    # 3. 提取文章实体信息 
    # 文章 ID 通常是 URL 最后的数字
    article_id = url.split('/')[-1]
    article_data = data['initialState']['entities']['articles'].get(article_id)
    
    if not article_data:
        print("未能解析到文章内容")
        return

    title = article_data['title'] # [cite: 1, 11]
    author = article_data['author']['name'] # [cite: 11, 54]
    content_html = article_data['content'] # 
    publish_time = article_data.get('updated', article_data.get('created')) # [cite: 11]

    # 创建保存目录
    safe_title = re.sub(r'[\\/:*?"<>|]', '_', title)
    base_dir = f"archive_{article_id}"
    img_dir = os.path.join(base_dir, "images")
    os.makedirs(img_dir, exist_ok=True)

    # 4. 处理图片：将 HTML 中的图片链接替换为本地下载路径
    content_soup = BeautifulSoup(content_html, 'html.parser')
    for img_tag in content_soup.find_all('img'):
        # 知乎通常将真实路径放在 data-actualsrc 或 data-original 中
        actual_src = img_tag.get('data-original') or img_tag.get('data-actualsrc') or img_tag.get('src')
        if actual_src:
            local_path = download_image(actual_src, img_dir)
            img_tag['src'] = local_path

    # 5. 转换为 Markdown
    markdown_text = md(str(content_soup), heading_style="ATX")
    
    # 拼接最终文件内容
    md_header = f"# {title}\n\n**作者:** {author}\n**原始链接:** {url}\n\n---\n\n"
    final_md = md_header + markdown_text

    # 保存文件
    with open(os.path.join(base_dir, f"{safe_title}.md"), "w", encoding="utf-8") as f:
        f.write(final_md)

    print(f"存档完成！文件保存在: {base_dir}")

if __name__ == "__main__":
    target_url = "https://zhuanlan.zhihu.com/p/1993458822560363213"
    parse_zhihu_column(target_url)