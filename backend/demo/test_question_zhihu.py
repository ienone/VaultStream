import os
import re
import json
import requests
from datetime import datetime
from bs4 import BeautifulSoup
from markdownify import markdownify as md

# 请确保此处填充了您 F12 获取的完整 Headers
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

def format_ts(ts):
    """将 Unix 时间戳转换为标准时间字符串"""
    return datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S') if ts else "N/A"

def download_image(url, save_dir):
    """下载图片并返回本地路径"""
    if not url or "http" not in url: return url
    try:
        clean_url = url.split('?')[0]
        img_name = clean_url.split('/')[-1]
        img_path = os.path.join(save_dir, img_name)
        if not os.path.exists(img_path):
            resp = requests.get(url, headers=HEADERS, timeout=10)
            if resp.status_code == 200:
                with open(img_path, 'wb') as f: f.write(resp.content)
        return f"./images/{img_name}"
    except: return url

def parse_zhihu_question_full(url):
    question_id = url.split('/')[-1]
    response = requests.get(url, headers=HEADERS)
    response.encoding = 'utf-8'
    soup = BeautifulSoup(response.text, 'html.parser')

    # 1. 提取原始 JSON
    data_script = soup.find('script', id='js-initialData')
    if not data_script:
        print("未能提取到数据，请检查 Cookie 有效性")
        return
    
    data = json.loads(data_script.string)
    entities = data['initialState']['entities']
    q_data = entities['questions'].get(question_id)

    if not q_data:
        print(f"在 JSON 实体中未找到问题 ID: {question_id}")
        return

    # 2. 字段全提取 
    meta = {
        "title": q_data.get('title'),
        "id": q_data.get('id'),
        "type": q_data.get('questionType'), # 提问类型 
        "created_at": format_ts(q_data.get('created')), # 提问时间 
        "updated_at": format_ts(q_data.get('updatedTime')), # 修改时间 
        "visit_count": q_data.get('visitCount'), # 浏览量 
        "answer_count": q_data.get('answerCount'), # 回答数 
        "follower_count": q_data.get('followerCount'), # 关注数 
        "comment_count": q_data.get('commentCount'), # 评论数 
        "is_muted": q_data.get('isMuted'),
        "is_normal": q_data.get('isNormal'),
        "tags": [t['name'] for t in q_data.get('topics', [])], # 话题 Tag 
    }

    # 3. 作者深度解析 
    author_raw = q_data.get('author', {})
    author = {
        "name": author_raw.get('name'),
        "headline": author_raw.get('headline'),
        "avatar": author_raw.get('avatarUrl'),
        "url": f"https://www.zhihu.com/people/{author_raw.get('urlToken')}",
        "gender": "男" if author_raw.get('gender') == 1 else "女"
    }

    # 4. 创建存档文件夹
    base_dir = f"archive_question_{question_id}"
    img_dir = os.path.join(base_dir, "images")
    os.makedirs(img_dir, exist_ok=True)

    # 5. 正文描述转换及图片保存 
    detail_html = q_data.get('detail', '')
    detail_soup = BeautifulSoup(detail_html, 'html.parser')
    for img in detail_soup.find_all('img'):
        src = img.get('data-original') or img.get('data-actualsrc') or img.get('src')
        img['src'] = download_image(src, img_dir)
    
    description_md = md(str(detail_soup), heading_style="ATX")

    # 6. 回答预览卡片处理 
    answer_previews = []
    for aid, a_info in entities.get('answers', {}).items():
        a_author = a_info.get('author', {})
        answer_previews.append({
            "name": a_author.get('name'),
            "link": f"https://www.zhihu.com/question/{question_id}/answer/{aid}",
            "avatar": a_author.get('avatarUrl')
        })

    # 7. 写入 Markdown 
    md_header = f"""# {meta['title']}

## 提问元数据
- **问题 ID**: {meta['id']}
- **提问类型**: {meta['type']}
- **创建时间**: {meta['created_at']}
- **最后修改**: {meta['updated_at']}
- **统计数据**: {meta['visit_count']} 浏览 | {meta['follower_count']} 关注 | {meta['answer_count']} 回答 | {meta['comment_count']} 评论
- **标签**: {', '.join(meta['tags'])}
- **状态**: {'正常' if meta['is_normal'] else '非正常'} | {'已屏蔽' if meta['is_muted'] else '未屏蔽'}

## 作者信息
- **昵称**: [{author['name']}]({author['url']})
- **性别**: {author['gender']}
- **签名**: {author['headline']}

---

## 问题描述

{description_md}

---

##  回答预览 ({len(answer_previews)} 个)
"""
    for ap in answer_previews:
        md_header += f"- **{ap['name']}**: [点击查看回答]({ap['link']})\n"

    # 保存文件
    file_path = os.path.join(base_dir, "index.md")
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(md_header)
    
    # 额外保存一个 metadata.json 供 Flutter 方便调用
    with open(os.path.join(base_dir, "metadata.json"), "w", encoding="utf-8") as f:
        json.dump({"meta": meta, "author": author, "previews": answer_previews}, f, ensure_ascii=False, indent=4)

    print(f"存档成功！请查看文件夹: {base_dir}")

if __name__ == "__main__":
    url = "https://www.zhihu.com/question/20917550"
    parse_zhihu_question_full(url)