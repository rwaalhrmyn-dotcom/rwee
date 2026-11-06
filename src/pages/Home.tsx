import { Link } from 'react-router-dom'
import RawaaAssistant from '../components/RawaaAssistant'

export default function Home() {
  return (
    <>
      {/* بانر أنيق علوي */}
      <div className="promo">
        <div>
          <h3>كل ما يحتاجه المكان، يصل بعناية</h3>
          <p>مياه ومصاحف ومستلزمات المساجد — طلب واحد، توصيل موثوق إلى أربع مدن.</p>
        </div>
        <Link className="btn" to="/products">تسوّق الآن ←</Link>
      </div>

      {/* مساعد رِواء الذكي */}
      <RawaaAssistant />

      <section className="hero">
        <img src="/hero.png" alt="رواء الحرمين" />
        <div>
          <div className="eyebrow">— من قلب الحرمين، إلى كل مكان</div>
          <h1>احتياجات جمعيتك، تصل بعناية.</h1>
          <p className="muted">المياه والمصاحف ومستلزمات المساجد في تجربة شراء واحدة واضحة. اطلب من الموردين ونسّق التوصيل في مكة والمدينة وجدة والطائف.</p>
          <div style={{ display: 'flex', gap: 12, marginTop: 20 }}>
            <Link className="btn" to="/products">اكتشف المنتجات ←</Link>
            <Link className="btn ghost" to="/suppliers">الموردون</Link>
          </div>
        </div>
      </section>

      {/* بانر التصدّق والإهداء */}
      <div className="gift">
        <div>
          <h3 style={{ margin: '0 0 6px' }}>تصدّق بحب، على من تحب 🤍</h3>
          <p style={{ margin: 0 }}>أهدِ مياهاً ومصاحف ومستلزمات باسم من تحب، أو اجعلها صدقة جارية تصل حيث الحاجة.</p>
        </div>
        <Link className="btn" to="/gifts">ابدأ الإهداء ←</Link>
      </div>

      <section className="grid" style={{ gridTemplateColumns: 'repeat(3,1fr)', margin: '24px 0' }}>
        {[['تفاصيل واضحة', 'كل منتج بوحدته وسعره ومدينته'],
          ['أربع مدن، عناية واحدة', 'مكة، المدينة، جدة، الطائف'],
          ['متابعة التوصيل', 'من الاختيار إلى الاستلام']].map(([t, d]) => (
          <div className="card" key={t}><strong style={{ color: 'var(--green)' }}>{t}</strong><p className="muted" style={{ margin: '8px 0 0' }}>{d}</p></div>
        ))}
      </section>
    </>
  )
}
