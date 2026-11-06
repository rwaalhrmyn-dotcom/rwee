import { Link, NavLink, Outlet } from 'react-router-dom'

export default function Layout() {
  return (
    <>
      <div className="topbar">نخدم مكة والمدينة وجدة والطائف · من اختيارك، إلى باب المستفيد</div>
      <header className="nav">
        <div className="container">
          <Link to="/" className="brand">رِواء الحرمين<small>عناية تصل إلى حيث تحتاجها</small></Link>
          <nav className="navlinks">
            <NavLink to="/" end>الرئيسية</NavLink>
            <NavLink to="/products">تسوّق المنتجات</NavLink>
            <NavLink to="/bundles">الباقات والتوريد الدوري</NavLink>
            <NavLink to="/business">توريد الجمعيات الخيرية</NavLink>
            <NavLink to="/needs">احتياجات الجمعية</NavLink>
            <NavLink to="/suppliers">الموردون</NavLink>
            <NavLink to="/gifts">أهدِ من تحب</NavLink>
            <NavLink to="/cart">السلة</NavLink>
            <NavLink to="/customer">حسابي</NavLink>
            <NavLink to="/loyalty">مكافآت رِواء</NavLink>
            <NavLink to="/supplier">بوابة المورد</NavLink>
            <NavLink to="/admin">الإدارة</NavLink>
          </nav>
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
              <h4>التسوّق</h4>
              <Link to="/products">المنتجات</Link>
              <Link to="/suppliers">الموردون</Link>
              <Link to="/gifts">أهدِ من تحب</Link>
              <Link to="/bundles">الباقات والتوريد الدوري</Link>
              <Link to="/business">توريد الجمعيات</Link>
              <Link to="/needs">احتياجات الجمعية</Link>
              <Link to="/cart">السلة</Link>
            </div>
            <div>
              <h4>حسابك</h4>
              <Link to="/customer">طلباتي</Link>
              <Link to="/loyalty">مكافآت رِواء</Link>
              <Link to="/customer/login">تسجيل الدخول</Link>
            </div>
            <div>
              <h4>الشركاء</h4>
              <Link to="/supplier">بوابة المورد</Link>
              <Link to="/supplier/register">انضم كمورد</Link>
              <Link to="/admin">الإدارة</Link>
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
