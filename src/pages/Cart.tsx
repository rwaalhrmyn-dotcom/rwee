import { useCart } from '../context/CartContext'
import { sar } from '../lib/format'
import { Link } from 'react-router-dom'

export default function Cart() {
  const { items, remove, clear, total } = useCart()
  return (
    <section style={{ padding: '24px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>سلة المشتريات</h2>
      {items.length === 0 ? (
        <p className="muted">سلتك فارغة. <Link to="/products" style={{ color: 'var(--green)' }}>تصفّح المنتجات ←</Link></p>
      ) : (
        <div className="card" style={{ maxWidth: 560 }}>
          {items.map(i => (
            <div key={i.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '10px 0', borderBottom: '1px solid var(--border)' }}>
              <div><strong>{i.name}</strong><div className="muted" style={{ fontSize: 13 }}>×{i.qty}</div></div>
              <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
                <span className="price">{sar(i.price_halalas * i.qty)}</span>
                <button className="badge" style={{ border: 0, cursor: 'pointer' }} onClick={() => remove(i.id)}>حذف</button>
              </div>
            </div>
          ))}
          <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 16, fontWeight: 700 }}>
            <span>الإجمالي</span><span className="price">{sar(total)}</span>
          </div>
          <div className="note" style={{ marginTop: 14 }}>إتمام الطلب يتطلب تسجيل دخول العميل عبر رمز التحقق. <Link to="/customer/login" style={{ color: 'var(--green)' }}>سجّل الدخول ←</Link></div>
          <button className="btn ghost" style={{ marginTop: 12 }} onClick={clear}>تفريغ السلة</button>
        </div>
      )}
    </section>
  )
}
