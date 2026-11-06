import { Link } from 'react-router-dom'

export default function Home() {
  return (
    <>
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
