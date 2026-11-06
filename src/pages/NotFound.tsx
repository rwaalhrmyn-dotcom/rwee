import { Link } from 'react-router-dom'
export default function NotFound() {
  return <section className="center" style={{ padding: '60px 0' }}>
    <h2 style={{ color: 'var(--green)' }}>الصفحة غير موجودة</h2>
    <Link className="btn" to="/">العودة للرئيسية</Link>
  </section>
}
