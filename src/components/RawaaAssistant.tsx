import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useI18n } from '../lib/i18n'

const CHIPS = [
  { t: 'أحتاج مياه', q: 'مياه' },
  { t: 'المصاحف وحواملها', q: 'مصاحف' },
  { t: 'مستلزمات المساجد', q: 'مستلزمات' },
  { t: 'كيف أتابع التوصيل؟', q: 'تتبع' },
]

function answer(q: string): { text: string; to?: string } {
  const s = q.trim()
  if (/مياه|ماء/.test(s)) return { text: 'لدينا مياه معبّأة بأحجام متعددة. اعرض قسم المياه الآن.', to: '/products?cat=water' }
  if (/مصحف|مصاحف|قرآن|حامل/.test(s)) return { text: 'المصاحف وحواملها متوفرة في قسم المصاحف.', to: '/products?cat=quran' }
  if (/مستلزم|مسجد|سجاد|تجهيز/.test(s)) return { text: 'مستلزمات وتجهيزات المساجد في قسم المستلزمات.', to: '/products?cat=supplies' }
  if (/تتبع|توصيل|طلب|شحن|أين/.test(s)) return { text: 'تابع طلباتك وحالتها من صفحة حسابي.', to: '/customer' }
  if (/مورد|بائع|انضم/.test(s)) return { text: 'انضم كمورد وأدِر منتجاتك من بوابة المورد.', to: '/supplier' }
  if (/هدية|أهدي|تصدق|صدقة/.test(s)) return { text: 'يمكنك أن تُهدي من تحب.', to: '/gifts' }
  return { text: 'تصفّح جميع المنتجات، وسنساعدك في الوصول لما تحتاجه.', to: '/products' }
}

export default function RawaaAssistant() {
  const [q, setQ] = useState('')
  const [ans, setAns] = useState<{ text: string; to?: string } | null>(null)
  const nav = useNavigate()
  const { t } = useI18n()
  const ask = (text: string) => { const a = answer(text); setAns(a) }
  return (
    <div className="assistant">
      <div style={{ display: 'flex', gap: 10, alignItems: 'center', marginBottom: 10 }}>
        <span style={{ fontSize: 22 }}>✦</span>
        <div><strong style={{ color: 'var(--green)' }}>{t('asstTitle')}</strong>
          <div className="muted" style={{ fontSize: 13 }}>{t('asstSub')}</div></div>
      </div>
      <div className="row">
        <input value={q} onChange={e => setQ(e.target.value)} onKeyDown={e => e.key === 'Enter' && ask(q)}
          placeholder={t('asstPlaceholder')} />
        <button className="btn" onClick={() => ask(q)}>{t('ask')}</button>
      </div>
      <div className="chips">
        {CHIPS.map(c => <span key={c.t} className="chip" onClick={() => { setQ(c.t); ask(c.q) }}>{c.t}</span>)}
      </div>
      {ans && (
        <div className="ans">
          {ans.text}
          {ans.to && <div style={{ marginTop: 8 }}><button className="btn ghost" style={{ padding: '6px 16px' }} onClick={() => nav(ans.to!)}>{t('go')}</button></div>}
        </div>
      )}
    </div>
  )
}
