import { useState } from 'react'
import { Link, NavLink, Outlet } from 'react-router-dom'
import { useCart } from '../context/CartContext'

export default function Layout() {
  const { items } = useCart()
  const count = items.reduce((s, i) => s + i.qty, 0)
  const [open, setOpen] = useState(false)

  return (
    <>
      <div className="topbar">نخدم مكة والمدينة وجدة والطائف · من اختيارك، إلى باب المستفيد</div>
      <header className="nav2">
        <div className="container">
          <div className="bar">
            <Link to="/" className="brand" onClick={() => setOpen(false)}>رِواء الحرمين<small>عناية تصل إلى حيث تحتاجها</small></Link>

            <nav className="menu">
              <div className="item"><NavLink to="/" end>الرئيسية</NavLink></div>

              <div className="item">
                <button>المنتجات <span className="caret">▾</span></button>
                <div className="drop">
                  <Link to="/products">تسوّق كل المنتجات</Link>
                  <div className="lbl">الفئات</div>
                  <Link to="/products?cat=water">المياه والسقيا</Link>
                  <Link to="/products?cat=quran">المصاحف وحواملها</Link>
                  <Link to="/products?cat=supplies">مستلزمات المساجد</Link>
                  <Link to="/products?cat=food">الأغذية</Link>
                  <Link to="/products?cat=equipment">التجهيزات</Link>
                  <div className="sep" />
                  <Link to="/bundles">الباقات والتوريد الدوري</Link>
                </div>
              </div>

              <div className="item">
                <button>الموردون <span className="caret">▾</span></button>
                <div className="drop">
                  <Link to="/suppliers">قائمة الموردين</Link>
                  <Link to="/compare">مقارنة الموردين</Link>
                  <div className="sep" />
                  <Link to="/supplier/register">انضم كمورد</Link>
                  <Link to="/supplier">بوابة المورد</Link>
                </div>
              </div>

              <div className="item">
                <button>الجمعيات والعروض <span className="caret">▾</span></button>
                <div className="drop">
                  <Link to="/business">توريد الجمعيات الخيرية</Link>
                  <Link to="/business">طلب عرض توريد</Link>
                  <Link to="/needs">احتياجات الجمعية</Link>
                  <div className="sep" />
                  <Link to="/bundles">الباقات والتوريد الدوري</Link>
                </div>
              </div>

              <div className="item"><NavLink to="/gifts">أهدِ من تحب</NavLink></div>
              <div className="item"><NavLink to="/loyalty">مكافآت رِواء</NavLink></div>
            </nav>

            <div className="right">
              <Link to="/cart" className="iconbtn" title="السلة">🛒{count > 0 && <span className="cartcount">{count}</span>}</Link>
              <div className="item" style={{ position: 'relative' }}>
                <button className="iconbtn" title="حسابي">👤</button>
                <div className="drop" style={{ insetInlineStart: 'auto', insetInlineEnd: 0 }}>
                  <Link to="/customer">حسابي وطلباتي</Link>
                  <Link to="/delivery">توثيق التسليم</Link>
                  <Link to="/loyalty">مكافآت رِواء</Link>
                  <div className="sep" />
                  <Link to="/customer/login">تسجيل دخول العميل</Link>
                  <Link to="/supplier">بوابة المورد</Link>
                  <Link to="/admin">لوحة الإدارة</Link>
                </div>
              </div>
              <button className="iconbtn hamb" onClick={() => setOpen(o => !o)} title="القائمة">☰</button>
            </div>
          </div>

          <div className={'m-menu' + (open ? ' open' : '')} onClick={() => setOpen(false)}>
            <NavLink to="/" end>الرئيسية</NavLink>
            <div className="lbl">المنتجات</div>
            <NavLink to="/products">تسوّق كل المنتجات</NavLink>
            <NavLink to="/products?cat=water">المياه</NavLink>
            <NavLink to="/products?cat=quran">المصاحف</NavLink>
            <NavLink to="/products?cat=supplies">المستلزمات</NavLink>
            <NavLink to="/bundles">الباقات والتوريد الدوري</NavLink>
            <div className="lbl">الموردون</div>
            <NavLink to="/suppliers">قائمة الموردين</NavLink>
            <NavLink to="/compare">مقارنة الموردين</NavLink>
            <NavLink to="/supplier/register">انضم كمورد</NavLink>
            <div className="lbl">الجمعيات والعروض</div>
            <NavLink to="/business">توريد الجمعيات / طلب عرض</NavLink>
            <NavLink to="/needs">احتياجات الجمعية</NavLink>
            <div className="lbl">حسابك</div>
            <NavLink to="/gifts">أهدِ من تحب</NavLink>
            <NavLink to="/loyalty">مكافآت رِواء</NavLink>
            <NavLink to="/customer">حسابي وطلباتي</NavLink>
            <NavLink to="/delivery">توثيق التسليم</NavLink>
            <NavLink to="/supplier">بوابة المورد</NavLink>
            <NavLink to="/admin">لوحة الإدارة</NavLink>
          </div>
        </div>
      </header>

      <main className="container"><Outlet /></main>

      <footer className="footer">
        <div className="container">
          <div className="ftr-grid">
            <div>
              <div className="brand" style={{ marginBottom: 8 }}>رِواء الحرمين</div>
              <p className="muted" style={{ margin: 0, maxWidth: 320 }}>سوق المياه والمصاحف ومستلزمات المساجد في مكة والمدينة وجدة والطائف، مع خدمات توصيل موثوقة.</p>
            </div>
            <div>
              <h4>المنتجات</h4>
              <Link to="/products">تسوّق المنتجات</Link>
              <Link to="/bundles">الباقات والتوريد الدوري</Link>
              <Link to="/gifts">أهدِ من تحب</Link>
            </div>
            <div>
              <h4>الموردون والجمعيات</h4>
              <Link to="/suppliers">الموردون</Link>
              <Link to="/compare">مقارنة الموردين</Link>
              <Link to="/business">توريد الجمعيات</Link>
              <Link to="/needs">احتياجات الجمعية</Link>
            </div>
            <div>
              <h4>حسابك</h4>
              <Link to="/customer">طلباتي</Link>
              <Link to="/loyalty">مكافآت رِواء</Link>
              <Link to="/delivery">توثيق التسليم</Link>
              <Link to="/terms">السياسة والخصوصية</Link>
            </div>
          </div>
          <div className="ftr-bottom">
            <span>© {new Date().getFullYear()} رِواء الحرمين — جميع الحقوق محفوظة</span>
            <span className="muted">مكة · المدينة · جدة · الطائف · بياناتك تبقى خاصة</span>
          </div>
        </div>
      </footer>
    </>
  )
}
