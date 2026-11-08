import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { useI18n } from '../lib/i18n'
import { supabase } from '../lib/supabase'
import { useCart } from '../context/CartContext'
import { sar } from '../lib/format'

type Product = { id: string; name: string; price_halalas: number; unit: string; category: string }

// Normalize Arabic: strip tashkeel, unify alef/hamza/ya/ta-marbuta, collapse spaces.
const norm = (s: string) => (s || '').toLowerCase()
  .replace(/[ً-ْٰـ]/g, '')
  .replace(/[إأآ]/g, 'ا').replace(/ى/g, 'ي').replace(/ة/g, 'ه').replace(/ؤ/g, 'و').replace(/ئ/g, 'ي')
  .replace(/\s+/g, ' ').trim()

const CAT_WORDS: Record<string, string> = {
  water: 'مياه ماء سقيا شرب قاروره عبوه كرتون شده لتر مل water',
  quran: 'مصحف مصاحف قران حامل حوامل رحل رحله quran',
  supplies: 'مستلزم مستلزمات مسجد سجاد فرش مناديل كاسات اكواب supplies',
  food: 'اكل طعام تمر غذاء وجبه افطار سحور food',
  equipment: 'تجهيزات معدات كرسي كراسي طاوله قابل للطي equipment',
}
const CAT_AR: Record<string, string> = { water: 'المياه', quran: 'المصاحف', supplies: 'المستلزمات', food: 'الأغذية', equipment: 'التجهيزات' }

const CHIPS = ['أحتاج مياه', 'المصاحف وحواملها', 'كراسي قابلة للطي', 'كيف أتابع طلبي؟', 'طرق الدفع']

type Reply = { text: string; to?: string; cta?: string; products?: Product[] }

export default function RawaaAssistant() {
  const [q, setQ] = useState('')
  const [reply, setReply] = useState<Reply | null>(null)
  const [busy, setBusy] = useState(false)
  const nav = useNavigate()
  const { t } = useI18n()
  const { add } = useCart()
  const en = t('home') === 'Home'

  // Warm welcome on first load.
  useEffect(() => {
    setReply({
      text: en
        ? 'Welcome to Rawaa Alharamain 🤍 How can I help you today? Ask me about products, your order, payment — or any problem you run into.'
        : 'أهلاً بك في رِواء الحرمين 🤍 كيف أقدر أساعدك اليوم؟ اسألني عن المنتجات أو طلبك أو الدفع — أو أخبرني بأي مشكلة تواجهك وسأساعدك في حلّها.',
    })
  }, [en])

  const detectCategory = (s: string): string | null => {
    for (const [cat, words] of Object.entries(CAT_WORDS))
      if (words.split(' ').some(w => w.length > 1 && s.includes(w))) return cat
    return null
  }

  const searchCatalog = async (term: string, cat: string | null): Promise<Product[]> => {
    let query = supabase.from('products').select('id,name,price_halalas,unit,category').limit(60)
    if (cat) query = query.eq('category', cat)
    const { data } = await query
    const list = (data || []) as Product[]
    const nt = norm(term)
    const words = nt.split(' ').filter(w => w.length > 1)
    const scored = list.map(p => {
      const nn = norm(p.name)
      let score = 0
      if (nt && nn.includes(nt)) score += 5
      for (const w of words) if (nn.includes(w)) score += 2
      if (cat && p.category === cat) score += 1
      return { p, score }
    }).filter(x => x.score > 0 || cat)
      .sort((a, b) => b.score - a.score)
    return scored.slice(0, 4).map(x => x.p)
  }

  const ask = async (raw: string) => {
    const text = raw.trim(); if (!text) return
    setBusy(true); setReply(null)
    const s = norm(text)

    // FAQ / intent routing
    const faq = (): Reply | null => {
      // ——— problem solving (priority) ———
      if (/(ما وصل|لم يصل|ماوصل|متاخر|متأخر|وين طلبي|اين طلبي|تاخر|ما استلمت)/.test(s))
        return { text: en ? "Sorry for the delay. Open your orders to see the live status; if it's overdue, message us on WhatsApp +966 53 199 5976 and we'll follow up right away." : 'نعتذر عن التأخير. افتح «طلباتي» لمتابعة الحالة لحظة بلحظة، وإن تأخّر الطلب راسلنا واتساب ‎+966 53 199 5976 وسنتابعه فوراً.', to: '/customer', cta: en ? 'My orders' : 'طلباتي' }
      if (/(الدفع ما|فشل الدفع|ما تم الدفع|مشكله في الدفع|الدفع لا يعمل|خصم|خُصم|انخصم|دفعت ولم|اتمام الدفع)/.test(s))
        return { text: en ? 'If a payment did not complete, your order stays pending and no amount is captured — just try paying again from your orders. If an amount was deducted without an order, contact us and we will resolve it.' : 'إن لم يكتمل الدفع يبقى طلبك معلّقاً ولا يُخصم أي مبلغ — أعد المحاولة من «طلباتي». وإن خُصم مبلغ دون طلب، تواصل معنا وسنحلّها فوراً: ‎+966 53 199 5976.', to: '/customer', cta: en ? 'My orders' : 'طلباتي' }
      if (/(الغاء|إلغاء|الغي|استرجاع|استرداد|ارجاع|refund)/.test(s))
        return { text: en ? 'To cancel or request a refund, contact us on WhatsApp +966 53 199 5976 or info@riwaalharamain.info with your order number and we will help.' : 'لإلغاء الطلب أو طلب استرجاع، تواصل معنا عبر واتساب ‎+966 53 199 5976 أو info@riwaalharamain.info مع رقم طلبك وسنساعدك.' }
      if (/(تالف|مكسور|ناقص|منتج خطا|غلط الطلب|مختلف|خطا في الطلب|جوده)/.test(s))
        return { text: en ? "Sorry about that. Send us a photo on WhatsApp +966 53 199 5976 and we'll arrange a replacement or refund." : 'نأسف لذلك. أرسل لنا صورة عبر واتساب ‎+966 53 199 5976 وسنرتّب استبدالاً أو استرداداً.' }
      if (/(مشكله|مشكلة|شكوى|اشتكي|مو راضي|غير راضي|ساعدني|مساعده|ماذا افعل|عطل)/.test(s))
        return { text: en ? "I'm here to help. Tell me briefly what happened, or reach us directly on WhatsApp +966 53 199 5976 · info@riwaalharamain.info." : 'أنا هنا لمساعدتك. أخبرني باختصار بما حدث، أو تواصل معنا مباشرة عبر واتساب ‎+966 53 199 5976 · info@riwaalharamain.info.' }
      // ——— general ———
      if (/(تتبع|تابع|وين|اين|حاله|طلبي|طلبات|شحنه|توصيل وصل)/.test(s))
        return { text: en ? 'Track your orders and their status from your account page.' : 'تابع طلباتك وحالتها من صفحة «حسابي».', to: '/customer', cta: en ? 'My orders' : 'طلباتي' }
      if (/(دفع|ادفع|فيزا|مدى|مدا|ابل|apple|بطاقه|ضريبه|ضريبة|vat|سعر التوصيل|رسوم)/.test(s))
        return { text: en ? 'We accept mada, Visa and Apple Pay via Tap. Prices include 15% VAT.' : 'نقبل مدى وVisa وApple Pay عبر Tap، والأسعار شاملة ضريبة القيمة المضافة 15٪.' }
      if (/(توصيل|شحن|يوصل|تغطيه|مكان التوصيل|خريطه)/.test(s))
        return { text: en ? 'We deliver to mosques and homes. Pin your exact location on the map at checkout.' : 'نوصّل للمساجد والمنازل. حدّد موقعك بدقّة على الخريطة عند إتمام الطلب.', to: '/products', cta: en ? 'Shop now' : 'تسوّق الآن' }
      if (/(تواصل|اتصال|واتس|whatsapp|رقم|جوال|ايميل|بريد|دعم|شكوى|خدمه العملاء)/.test(s))
        return { text: en ? 'Contact us: +966 53 199 5976 (call / WhatsApp) · info@riwaalharamain.info' : 'تواصل معنا: ‎+966 53 199 5976 (اتصال/واتساب) · info@riwaalharamain.info' }
      if (/(ولاء|نقاط|مكافا|مكافآت|خصم)/.test(s))
        return { text: en ? 'Rawaa Rewards gives you points with every order.' : 'برنامج مكافآت رِواء يمنحك نقاطاً مع كل طلب.', to: '/loyalty', cta: en ? 'Rewards' : 'المكافآت' }
      if (/(مورد|بائع|انضم|اسجل كمورد|شركه|منشاه|تاجر)/.test(s))
        return { text: en ? 'Join as a supplier and manage your products from the supplier portal.' : 'انضم كمورد وأدِر منتجاتك من بوابة المورد.', to: '/supplier/register', cta: en ? 'Join' : 'انضم كمورد' }
      if (/(هديه|اهدي|اهداء|صدقه|باسم من احب|من تحب)/.test(s))
        return { text: en ? 'Gift water, Qurans or supplies in a loved one’s name.' : 'أهدِ مياهاً أو مصاحف أو مستلزمات باسم من تحب.', to: '/gifts', cta: en ? 'Gift now' : 'ابدأ الإهداء' }
      if (/(باقه|باقات|اشتراك|توريد دوري|شهري|اسبوعي)/.test(s))
        return { text: en ? 'Order a weekly or monthly recurring supply.' : 'اطلب توريداً دورياً أسبوعياً أو شهرياً.', to: '/bundles', cta: en ? 'Bundles' : 'الباقات' }
      return null
    }

    const f = faq()
    if (f) { setReply(f); setBusy(false); return }

    // Otherwise: live catalog search
    const cat = detectCategory(s)
    const products = await searchCatalog(text, cat)
    setBusy(false)
    if (products.length > 0) {
      setReply({
        text: cat
          ? (en ? `Here is what we have in ${CAT_AR[cat]}:` : `إليك ما لدينا في ${CAT_AR[cat]}:`)
          : (en ? 'Closest matches I found:' : 'أقرب ما وجدته لك:'),
        products,
        to: cat ? `/products?cat=${cat}` : '/products',
        cta: en ? 'Browse all' : 'تصفّح الكل',
      })
    } else {
      setReply({
        text: en ? "I couldn't find a match. Browse all products and I'll help you narrow down."
          : 'لم أجد تطابقاً مباشراً. تصفّح جميع المنتجات وسأساعدك في الوصول لما تريد.',
        to: '/products', cta: en ? 'All products' : 'كل المنتجات',
      })
    }
  }

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
        <button className="btn" disabled={busy} onClick={() => ask(q)}>{busy ? '…' : t('ask')}</button>
      </div>
      <div className="chips">
        {CHIPS.map(c => <span key={c} className="chip" onClick={() => { setQ(c); ask(c) }}>{c}</span>)}
      </div>
      {reply && (
        <div className="ans">
          {reply.text}
          {reply.products && reply.products.length > 0 && (
            <div style={{ marginTop: 10, display: 'grid', gap: 8 }}>
              {reply.products.map(p => (
                <div key={p.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, background: '#fff', border: '1px solid var(--line)', borderRadius: 12, padding: '8px 12px' }}>
                  <div><strong style={{ fontSize: 14 }}>{p.name}</strong> <span className="muted" style={{ fontSize: 12 }}>· {p.unit}</span><div className="price" style={{ fontSize: 15 }}>{sar(p.price_halalas)}</div></div>
                  <button className="btn" style={{ padding: '6px 12px', fontSize: 13 }} onClick={() => add({ id: p.id, name: p.name, price_halalas: p.price_halalas })}>{en ? 'Add' : 'أضف'}</button>
                </div>
              ))}
            </div>
          )}
          {reply.to && <div style={{ marginTop: 10 }}><button className="btn ghost" style={{ padding: '6px 16px' }} onClick={() => nav(reply.to!)}>{reply.cta || t('go')}</button></div>}
        </div>
      )}
    </div>
  )
}
