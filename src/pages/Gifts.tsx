import { Link } from 'react-router-dom'
import { useSeo } from '../lib/seo'
export default function Gifts() {
  useSeo('أهدِ من تحب','أهدِ مياهاً ومصاحف ومستلزمات باسم من تحب — عطاء يصل حيث الحاجة.')
  return (
    <section style={{ padding: '32px 0' }}>
      <div className="eyebrow">— أهدِ من تحب</div>
      <h2 style={{ color: 'var(--green)' }}>أهدِ من تحب، بحبّ</h2>
      <p className="muted" style={{ maxWidth: 640 }}>اجعل عطاءك وصلةً لأحبّتك: أهدِ مياهاً ومصاحف ومستلزمات لمسجد أو جمعية باسم من تحب، عطاءً مستمراً يصل حيث الحاجة. منصة غير ربحية بروح العطاء.</p>
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(260px,1fr))', marginTop: 20 }}>
        {[['إهداء باسم من تحب', 'اختر المنتجات وسنوصلها مع بطاقة إهداء.', '/products'],
          ['عطاء مستمر', 'ساهم في تجهيز المساجد عطاءً مستمراً باسم من تحب.', '/products?cat=supplies'],
          ['وقف المصاحف', 'أوقف مصاحف تُقرأ في الحرمين وما حولهما.', '/products?cat=quran']].map(([t, d, to]) => (
          <div className="card" key={t}>
            <h3 style={{ color: 'var(--green)', marginTop: 0 }}>{t}</h3>
            <p className="muted">{d}</p>
            <Link className="btn" to={to}>ابدأ الإهداء ←</Link>
          </div>
        ))}
      </div>
    </section>
  )
}
