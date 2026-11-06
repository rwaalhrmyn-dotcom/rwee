import { Link } from 'react-router-dom'
export default function Gifts() {
  return (
    <section style={{ padding: '32px 0' }}>
      <div className="eyebrow">— أهدِ من تحب</div>
      <h2 style={{ color: 'var(--green)' }}>تصدّق بحب، على من تحب</h2>
      <p className="muted" style={{ maxWidth: 640 }}>اجعل عطاءك وصلةً لأحبّتك: أهدِ مياهاً ومصاحف ومستلزمات لمسجد أو جمعية باسم من تحب، أو تصدّق صدقة جارية تصل حيث الحاجة في مكة والمدينة وجدة والطائف.</p>
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fill,minmax(260px,1fr))', marginTop: 20 }}>
        {[['إهداء باسم من تحب', 'اختر المنتجات وسنوصلها مع بطاقة إهداء.', '/products'],
          ['صدقة جارية', 'ساهم في تجهيز المساجد كصدقة مستمرة.', '/products?cat=supplies'],
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
