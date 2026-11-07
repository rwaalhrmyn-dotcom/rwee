import { Link } from 'react-router-dom'
import RawaaAssistant from '../components/RawaaAssistant'
import { useI18n } from '../lib/i18n'
import { useSeo } from '../lib/seo'

export default function Home() {
  const { t } = useI18n()
  useSeo('بيع وتوصيل المياه للمساجد والمنازل', 'منصة تجارية متخصصة في بيع وتوصيل المياه للمساجد والمنازل، مع المصاحف ومستلزمات المساجد، بعناية وموثوقية.')
  const en = t('home') === 'Home'
  return (
    <>
      {/* بانر علوي جديد */}
      <div className="promo">
        <div>
          <div className="eyebrow" style={{ color: 'var(--gold-2)' }}>{en ? '— Water delivery to mosques & homes' : '— توصيل المياه للمساجد والمنازل'}</div>
          <h3>{en ? 'Everything you need — delivered with care' : 'كل ما تحتاجه يصل بعناية'}</h3>
          <p>{en ? 'A commercial platform specialized in selling and delivering water to mosques and homes — with Qurans and mosque supplies too.' : 'منصة تجارية متخصصة في بيع وتوصيل المياه للمساجد والمنازل — مع المصاحف ومستلزمات المساجد.'}</p>
        </div>
        <Link className="btn" to="/products">{t('shopNow')}</Link>
      </div>

      <RawaaAssistant />

      <section className="hero">
        <div className="imgwrap"><img src="/hero.png" alt="رواء الحرمين" /></div>
        <div>
          <div className="eyebrow">{t('heroEyebrow')}</div>
          <h1>{t('heroTitle')}</h1>
          <p className="muted" style={{ fontSize: 17 }}>{t('heroText')}</p>
          <div style={{ display: 'flex', gap: 12, marginTop: 24, flexWrap: 'wrap' }}>
            <Link className="btn" to="/products">{t('discover')}</Link>
            <Link className="btn ghost" to="/suppliers">{t('suppliers')}</Link>
          </div>
          <div style={{ display: 'flex', gap: 28, marginTop: 28, flexWrap: 'wrap' }}>
            {[[en ? 'The two Harams' : 'الحرمان', en ? 'Makkah · Madinah' : 'مكة المكرمة · المدينة المنورة'],
              [en ? 'Water delivery' : 'توصيل المياه', en ? 'To mosques & homes' : 'للمساجد والمنازل'],
              [en ? 'Trusted delivery' : 'توصيل موثوق', en ? 'From choice to door' : 'من الاختيار للباب']].map(([a, b]) => (
              <div key={a}><div style={{ fontWeight: 700, color: 'var(--green)', fontSize: 18 }}>{a}</div><div className="muted" style={{ fontSize: 13 }}>{b}</div></div>
            ))}
          </div>
        </div>
      </section>

      {/* كيف نعمل */}
      <div className="sec-head">
        <div className="eyebrow">{en ? '— How it works' : '— كيف نعمل'}</div>
        <h2>{en ? 'Three clear steps' : 'ثلاث خطوات واضحة'}</h2>
      </div>
      <section className="grid cols-3">
        {[['1', en ? 'Choose' : 'اختر', en ? 'Browse water, Qurans and supplies from approved suppliers.' : 'تصفّح المياه والمصاحف والمستلزمات من موردين معتمدين.'],
          ['2', en ? 'Order' : 'اطلب', en ? 'Place your order or request a recurring supply for your facility.' : 'اطلب أو اطلب توريداً دورياً لمنشأتك.'],
          ['3', en ? 'Receive' : 'استلم', en ? 'We coordinate trusted delivery with documented handover.' : 'ننسّق توصيلاً موثوقاً مع توثيق التسليم.']].map(([n, tt, d]) => (
          <div className="card" key={n}>
            <div style={{ width: 40, height: 40, borderRadius: 12, background: 'var(--soft)', color: 'var(--green)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 700, fontSize: 18 }}>{n}</div>
            <h3 style={{ color: 'var(--deep)', margin: '12px 0 6px' }}>{tt}</h3>
            <p className="muted" style={{ margin: 0 }}>{d}</p>
          </div>
        ))}
      </section>

      {/* بانر الإهداء الجديد */}
      <div className="gift">
        <div>
          <h3 style={{ margin: '0 0 7px' }}>{en ? 'Give with love, to those you love 🤍' : 'أهدِ من تحب، بحبّ 🤍'}</h3>
          <p style={{ margin: 0 }}>{en ? 'Gift water, Qurans and supplies in a loved one’s name — a gift that reaches where it matters.' : 'أهدِ مياهاً ومصاحف ومستلزمات باسم من تحب — عطاء يصل حيث الحاجة.'}</p>
        </div>
        <Link className="btn" to="/gifts">{t('giftStart')}</Link>
      </div>

      {/* مزايا */}
      <section className="grid cols-4" style={{ margin: '10px 0 8px' }}>
        {[['✦', en ? 'Clear details' : 'تفاصيل واضحة', en ? 'Unit, price and city per item' : 'الوحدة والسعر والمدينة لكل منتج'],
          ['◈', en ? 'Approved suppliers' : 'موردون معتمدون', en ? 'Verified establishments' : 'منشآت موثّقة'],
          ['❤', en ? 'Loyalty rewards' : 'مكافآت الولاء', en ? 'Earn with every order' : 'اكسب مع كل طلب'],
          ['⟳', en ? 'Recurring supply' : 'توريد دوري', en ? 'Weekly or monthly' : 'أسبوعي أو شهري']].map(([ic, tt, d]) => (
          <div className="card" key={tt}><div style={{ fontSize: 22, color: 'var(--gold-deep)' }}>{ic}</div><strong style={{ color: 'var(--green)', display: 'block', margin: '8px 0 4px' }}>{tt}</strong><span className="muted" style={{ fontSize: 13 }}>{d}</span></div>
        ))}
      </section>
    </>
  )
}
