import { z } from 'zod'
import { createHash } from 'node:crypto'

export interface Attachment { url: string; filename: string; mime_type?: string }
export interface Material { message_id: string; text: string; links: string[]; attachments: Attachment[] }
export interface AgentInput extends Material { user_id: string; quote?: Material; forwarded?: Material[] }

const capture = z.object({
  content_id: z.number().int(), capture_kind: z.string(), status: z.string(),
  title: z.string().nullable().optional(), author: z.string().nullable().optional(),
  summary: z.string().nullable().optional(), body: z.string().nullable().optional(),
  url: z.string().nullable().optional(), route: z.string(),
  collection_url: z.string().nullable().optional(),
  parse_error: z.object({ message: z.string().nullable(), type: z.string().nullable(), at: z.string().nullable() }).nullable().optional(),
})
const agentResult = z.object({
  session_id: z.string(), run_id: z.string(), status: z.string(), message: z.string(),
  confirmation_required: z.boolean(), confirmation: z.record(z.unknown()).nullable(),
  captures: z.array(capture), duplicate: z.boolean(),
})
const previewResult = z.object({
  duplicate: z.boolean(),
  items: z.array(z.object({
    url: z.string(), status: z.enum(['parsed', 'unsupported', 'failed']),
    platform: z.string().nullable().optional(), title: z.string().nullable().optional(),
    body: z.string().nullable().optional(), author: z.string().nullable().optional(),
    media_urls: z.array(z.string()), image_url: z.string().nullable(),
    text: z.string().nullable().optional(), reason: z.string().nullable().optional(),
    send_allowed: z.boolean(),
  })),
})
export type AgentResult = z.infer<typeof agentResult>
export type PreviewItem = z.infer<typeof previewResult>['items'][number]
export class VaultStreamError extends Error {
  constructor(message: string, readonly status?: number) { super(message) }
}

export class VaultStreamClient {
  private readonly baseUrl: string
  constructor(baseUrl: string, private readonly token: string, private readonly botConfigId: number) {
    const url = new URL(baseUrl)
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash) {
      throw new VaultStreamError('VaultStream API 地址无效。')
    }
    this.baseUrl = url.href.replace(/\/$/, '')
    if (!token.trim()) throw new VaultStreamError('请配置 VaultStream API Token。')
  }
  private async request<T>(path: string, schema: z.ZodType<T>, body?: unknown): Promise<T> {
    let response: Response
    try {
      response = await fetch(`${this.baseUrl}/bot/qq/${this.botConfigId}${path}`, {
        method: body === undefined ? 'GET' : 'POST',
        headers: { 'X-API-Token': this.token, ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
        body: body === undefined ? undefined : JSON.stringify(body),
        redirect: 'error', signal: AbortSignal.timeout(300_000),
      })
    } catch { throw new VaultStreamError('暂未收到 VaultStream 的处理结果；私聊任务会继续查询回执，请勿重复保存。') }
    if (!response.ok) throw new VaultStreamError(`VaultStream 请求失败（HTTP ${response.status}）。`, response.status)
    const result = schema.safeParse(await response.json())
    if (!result.success) throw new VaultStreamError('VaultStream 返回格式与接口契约不一致。')
    return result.data
  }
  runId(input: Pick<AgentInput, 'user_id' | 'message_id'>): string {
    const digest = createHash('sha256').update(`${this.botConfigId}:${input.user_id}:${input.message_id}`).digest('hex').slice(0, 40)
    return `qqrun_${digest}`
  }
  agent(input: AgentInput) { return this.request('/agent', agentResult, input) }
  receipt(runId: string, userId: string) {
    return this.request(`/agent/runs/${encodeURIComponent(runId)}?user_id=${encodeURIComponent(userId)}`, agentResult)
  }
  preview(groupId: string, userId: string, messageId: string, urls: string[]) {
    return this.request('/preview', previewResult, { group_id: groupId, user_id: userId, message_id: messageId, urls, reserve_send: true })
  }
}
