import { z } from 'zod'

const searchResponse = z.object({
  content_total: z.number().int(),
  content_has_more: z.boolean(),
  contents: z.array(z.object({
    content_id: z.number().int(),
    title: z.string().nullable(),
    url: z.string(),
    source_text: z.string().nullable(),
    match_source: z.string(),
  })),
})
const contentResponse = z.object({
  id: z.number().int(),
  title: z.string().nullable(),
  body: z.string().nullable(),
  url: z.string(),
})
const shareResponse = z.object({
  id: z.number().int(),
  platform: z.string(),
  url: z.string(),
  status: z.string(),
  created_at: z.string(),
})

export class VaultStreamError extends Error {}

export interface CaptureContext {
  bot_config_id: number
  bot_id: string
  chat_id: string
  user_id: string
  message_id: string
}

export class VaultStreamClient {
  private readonly baseUrl: string

  constructor(baseUrl: string, private readonly token: string) {
    const url = new URL(baseUrl)
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
      throw new VaultStreamError('VaultStream API 地址无效。')
    }
    this.baseUrl = url.href.replace(/\/$/, '')
    if (!token.trim()) throw new VaultStreamError('请配置 VaultStream API Token。')
  }

  private async request(path: string, body?: unknown): Promise<{ status: number; data: unknown }> {
    let response: Response
    try {
      response = await fetch(`${this.baseUrl}${path}`, {
        method: body === undefined ? 'GET' : 'POST',
        headers: { 'X-API-Token': this.token, ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
        body: body === undefined ? undefined : JSON.stringify(body),
        redirect: 'error',
        signal: AbortSignal.timeout(15_000),
      })
    } catch {
      throw new VaultStreamError(body === undefined
        ? 'VaultStream 暂时无法访问。'
        : '未收到保存结果，请先检查收藏库，避免重复提交。')
    }
    let data: unknown
    try { data = await response.json() } catch {
      throw new VaultStreamError('VaultStream 返回了无法读取的结果。')
    }
    return { status: response.status, data }
  }

  private parse<T>(response: { status: number; data: unknown }, schema: z.ZodType<T>): T {
    if (response.status !== 200) {
      if (response.status === 404) throw new VaultStreamError('收藏内容不存在。')
      if (response.status === 401 || response.status === 403) throw new VaultStreamError('VaultStream 拒绝了访问。')
      throw new VaultStreamError(`VaultStream 请求失败（HTTP ${response.status}）。`)
    }
    const result = schema.safeParse(response.data)
    if (!result.success) throw new VaultStreamError('VaultStream 返回格式与接口契约不一致。')
    return result.data
  }

  async search(query: string, page = 1) {
    const params = new URLSearchParams({ q: query, kind: 'contents', content_scope: 'library', mode: 'keyword', page: String(page), size: '5', top_k: '5' })
    const data = this.parse(await this.request(`/search/unified?${params}`), searchResponse)
    return {
      total: data.content_total,
      next_page: data.content_has_more ? page + 1 : null,
      items: data.contents.map(item => ({
        content_id: item.content_id, title: item.title, url: item.url,
        excerpt: item.source_text?.slice(0, 600) ?? '', match_source: item.match_source,
      })),
    }
  }

  async read(contentId: number, offset = 0) {
    const data = this.parse(await this.request(`/contents/${contentId}`), contentResponse)
    const body = data.body ?? ''
    return {
      content_id: data.id, title: data.title, url: data.url,
      body: body.slice(offset, offset + 6000),
      next_offset: body.length > offset + 6000 ? offset + 6000 : null,
    }
  }

  async save(url: string, context: CaptureContext) {
    const response = await this.request('/shares', { url, source: 'qq_bot', client_context: context })
    // /shares commits Content and ContentSource before queuing the parse task.
    if (response.status === 503) {
      const pending = z.object({ error_code: z.literal('parse_queue_unavailable'), content_id: z.number().int().positive() }).safeParse(response.data)
      if (pending.success) return { content_id: pending.data.content_id, saved: true, parsing_pending: true }
    }
    const data = this.parse(response, shareResponse)
    return { content_id: data.id, saved: true, parsing_pending: false, status: data.status }
  }
}
