import { h, Session } from 'koishi'
import type { AgentInput, Attachment, Material } from './client'

type Segment = { type: string; data: Record<string, any> }
type RawMessage = { message_id?: string | number; message?: Segment[] | string; content?: Segment[] | string }

export function extractLinks(text: string): string[] {
  const matches = text.match(/https?:\/\/[^\s<>\u3000]+/giu) ?? []
  return matches.map(value => value.replace(/[，。！？；：、）】》」』.,;!?]+$/u, '')).filter(value => {
    try { const u = new URL(value); return !!u.hostname && !u.username && !u.password } catch { return false }
  })
}
function cardLinks(value: unknown, output: string[], depth = 0): void {
  if (depth > 8 || !value || typeof value !== 'object') return
  for (const [key, item] of Object.entries(value)) {
    if (['qqdocurl', 'jumpurl', 'url', 'appurl'].includes(key.toLowerCase()) && typeof item === 'string') output.push(...extractLinks(item))
    else cardLinks(item, output, depth + 1)
  }
}
function normalizedSegments(content: string): Segment[] {
  return h.parse(content).map(element => ({ type: element.type, data: element.attrs }))
}
export async function readMessage(session: Session, includeAttachments = true): Promise<AgentInput> {
  const forwarded: Material[] = []
  const seen = new Set<string>()
  let quote: Material | undefined
  const internal = session.bot.internal
  async function collect(raw: RawMessage, id: string, depth: number): Promise<Material> {
    if (depth > 5) throw new Error('转发层级过深，请直接分享需要保存的内容。')
    const value = raw.message ?? raw.content ?? ''
    const segments = Array.isArray(value) ? value : normalizedSegments(value)
    const texts: string[] = [], links: string[] = [], attachments: Attachment[] = []
    for (const { type, data } of segments) {
      if (type === 'text') { const t = String(data.text ?? data.content ?? ''); texts.push(t); links.push(...extractLinks(t)) }
      else if (type === 'json') {
        try { cardLinks(JSON.parse(String(data.data)), links) } catch { throw new Error('分享卡片无法读取，请直接发送链接。') }
      } else if (type === 'forward') {
        const forwardId = String(data.id)
        if (seen.has(`forward:${forwardId}`)) continue
        seen.add(`forward:${forwardId}`)
        const nodes = await internal.getForwardMsg(forwardId) as RawMessage[]
        for (const [index, node] of nodes.entries()) {
          if (forwarded.length >= 20) throw new Error('一次最多处理 20 条转发，请分批分享。')
          forwarded.push(await collect(node, String(node.message_id ?? `${id}:forward:${index + 1}`), depth + 1))
        }
      } else if (type === 'node') {
        if (forwarded.length >= 20) throw new Error('一次最多处理 20 条转发，请分批分享。')
        forwarded.push(await collect({ content: data.content }, `${id}:node:${forwarded.length + 1}`, depth + 1))
      } else if (type === 'reply' && depth === 0) {
        const referenced = await internal.getMsg(String(data.id)) as RawMessage
        quote = await collect(referenced, String(data.id), depth + 1)
      } else if (type === 'onlinefile' && includeAttachments) {
        throw new Error('QQ 在线文件或文件夹暂不支持，请改为普通文件发送。')
      } else if (['image', 'img', 'video', 'record', 'audio', 'file'].includes(type)) {
        if (!includeAttachments) continue
        let url = String(data.url ?? data.src ?? '')
        if (!/^https?:\/\//i.test(url)) {
          if (type === 'file' && data.file_id) {
            const file = session.guildId
              ? await internal._get('get_group_file_url', { group_id: session.guildId, file_id: String(data.file_id) })
              : await internal._get('get_private_file_url', { file_id: String(data.file_id) })
            url = String(file.url ?? '')
          } else if (['image', 'img'].includes(type) && data.file) {
            const file = await internal.getImage(String(data.file))
            url = String(file.url ?? '')
          }
        }
        if (!/^https?:\/\//i.test(url)) throw new Error('QQ 未提供这个附件的可下载地址，请重新发送原文件。')
        const filename = String(data.name ?? data.filename ?? data.file ?? `${type}-${attachments.length + 1}`).split(/[\\/]/).pop() || type
        attachments.push({ url, filename })
      }
    }
    if (attachments.length > 10 || links.length > 20) throw new Error('一条消息最多处理 20 个链接或 10 个附件，请分批分享。')
    return { message_id: id, text: texts.join('\n'), links, attachments }
  }
  const raw = session.event._data as RawMessage | undefined
  const material = await collect(raw ?? { content: session.content }, session.messageId!, 0)
  if (!quote && session.quote) quote = await collect({ content: session.quote.content }, session.quote.id ?? `${session.messageId}:quote`, 1)
  return { ...material, user_id: session.userId!, ...(quote ? { quote } : {}), ...(forwarded.length ? { forwarded } : {}) }
}
