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
            <NavLink to="/suppliers">الموردون</NavLink>
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
        <div className="container">© رِواء الحرمين — مكة والمدينة وجدة والطائف · بيانات طلبك تبقى خاصة</div>
      </footer>
    </>
  )
}
