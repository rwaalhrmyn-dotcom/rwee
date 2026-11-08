import { useState } from 'react'
import { Link, NavLink, Outlet } from 'react-router-dom'
import { useCart } from '../context/CartContext'
import { useI18n, LANGS } from '../lib/i18n'
import PayMethods from './PayMethods'

export default function Layout() {
  const { items } = useCart()
  const count = items.reduce((s, i) => s + i.qty, 0)
  const { t, lang, setLang } = useI18n()
  const en = t('home') === 'Home'
  const [open, setOpen] = useState(false)
  const [langOpen, setLangOpen] = useState(false)
  const curLang = LANGS.find(l => l.code === lang)

  return (
    <>
      <div className="topbar">{t('topbar')}</div>
      <header className="nav2">
        <div className="container">
          <div className="bar">
            <Link to="/" className="brand" onClick={() => setOpen(false)}>رِواء الحرمين<small>{t('tagline')}</small></Link>

            <nav className="menu">
              <div className="item"><NavLink to="/" end>{t('home')}</NavLink></div>
              <div className="item">
                <button>{t('products')} <span className="caret">▾</span></button>
                <div className="drop">
                  <Link to="/products">{t('shopAll')}</Link>
                  <div className="lbl">{t('categories')}</div>
                  <Link to="/products?cat=water">{t('water')}</Link>
                  <Link to="/products?cat=quran">{t('quran')}</Link>
                  <Link to="/products?cat=supplies">{t('supplies')}</Link>
                  <Link to="/products?cat=food">{t('food')}</Link>
                  <Link to="/products?cat=equipment">{t('equipment')}</Link>
                  <div className="sep" /><Link to="/bundles">{t('bundles')}</Link>
                </div>
              </div>
              <div className="item">
                <button>{t('suppliers')} <span className="caret">▾</span></button>
                <div className="drop">
                  <Link to="/suppliers">{t('suppliersList')}</Link>
                  <Link to="/compare">{t('compare')}</Link>
                  <div className="sep" />
                  <Link to="/supplier/register">{t('joinSupplier')}</Link>
                  <Link to="/supplier">{t('supplierPortal')}</Link>
                </div>
              </div>
              <div className="item"><NavLink to="/gifts">{t('gifts')}</NavLink></div>
              <div className="item"><NavLink to="/loyalty">{t('loyalty')}</NavLink></div>
            </nav>

            <div className="right">
              {/* language switcher */}
              <div className="item" style={{ position: 'relative' }}>
                <button className="langbtn" onClick={() => setLangOpen(o => !o)} aria-label="language">🌐 <span>{curLang?.label}</span> <span className="caret">▾</span></button>
                {langOpen && (
                  <div className="langmenu" onMouseLeave={() => setLangOpen(false)}>
                    {LANGS.map(l => (
                      <button key={l.code} className={l.code === lang ? 'on' : ''} onClick={() => { setLang(l.code); setLangOpen(false) }}>{l.label}</button>
                    ))}
                  </div>
                )}
              </div>
              <Link to="/cart" className="iconbtn" title={t('cart')}>🛒{count > 0 && <span className="cartcount">{count}</span>}</Link>
              <div className="item" style={{ position: 'relative' }}>
                <button className="iconbtn" title={t('account')}>👤</button>
                <div className="drop" style={{ insetInlineStart: 'auto', insetInlineEnd: 0 }}>
                  <Link to="/customer">{t('myAccount')}</Link>
                  <Link to="/delivery">{t('deliveryDocs')}</Link>
                  <Link to="/loyalty">{t('loyalty')}</Link>
                  <div className="sep" />
                  <Link to="/customer/login">{t('customerLogin')}</Link>
                  <Link to="/supplier">{t('supplierPortal')}</Link>
                </div>
              </div>
              <button className="iconbtn hamb" onClick={() => setOpen(o => !o)} title={t('menu')} aria-label="menu">☰</button>
            </div>
          </div>

          <div className={'m-menu' + (open ? ' open' : '')} onClick={() => setOpen(false)}>
            <NavLink to="/" end>{t('home')}</NavLink>
            <div className="lbl">{t('products')}</div>
            <NavLink to="/products">{t('shopAll')}</NavLink>
            <NavLink to="/products?cat=water">{t('water')}</NavLink>
            <NavLink to="/products?cat=quran">{t('quran')}</NavLink>
            <NavLink to="/products?cat=supplies">{t('supplies')}</NavLink>
            <NavLink to="/bundles">{t('bundles')}</NavLink>
            <div className="lbl">{t('suppliers')}</div>
            <NavLink to="/suppliers">{t('suppliersList')}</NavLink>
            <NavLink to="/compare">{t('compare')}</NavLink>
            <NavLink to="/supplier/register">{t('joinSupplier')}</NavLink>
            <div className="lbl">{t('account')}</div>
            <NavLink to="/gifts">{t('gifts')}</NavLink>
            <NavLink to="/loyalty">{t('loyalty')}</NavLink>
            <NavLink to="/customer">{t('myAccount')}</NavLink>
            <NavLink to="/delivery">{t('deliveryDocs')}</NavLink>
            <NavLink to="/supplier">{t('supplierPortal')}</NavLink>
          </div>
        </div>
      </header>

      <main className="container"><Outlet /></main>

      <footer className="footer">
        <div className="container">
          <div className="ftr-grid">
            <div>
              <div className="brand" style={{ marginBottom: 8 }}>رِواء الحرمين</div>
              <p className="muted" style={{ margin: '0 0 12px', maxWidth: 320 }}>{t('ftrAbout')}</p>
              <h4>{t('contactUs')}</h4>
              <a href="tel:+966531995976" dir="ltr" style={{ textAlign: 'start' }}>📞 ‎+966 53 199 5976</a>
              <a href="https://wa.me/966531995976" target="_blank" rel="noopener" dir="ltr" style={{ textAlign: 'start' }}>💬 WhatsApp</a>
              <a href="mailto:rwaalhrmyn@gmail.com" dir="ltr" style={{ textAlign: 'start' }}>✉️ rwaalhrmyn@gmail.com</a>
            </div>
            <div>
              <h4>{t('ftrProducts')}</h4>
              <Link to="/products">{t('shopAll')}</Link>
              <Link to="/bundles">{t('bundles')}</Link>
              <Link to="/gifts">{t('gifts')}</Link>
            </div>
            <div>
              <h4>{t('ftrSuppliersOrgs')}</h4>
              <Link to="/suppliers">{t('suppliers')}</Link>
              <Link to="/compare">{t('compare')}</Link>
              <Link to="/supplier/register">{t('joinSupplier')}</Link>
            </div>
            <div>
              <h4>{t('ftrAccount')}</h4>
              <Link to="/customer">{t('myOrders')}</Link>
              <Link to="/loyalty">{t('loyalty')}</Link>
              <Link to="/delivery">{t('deliveryDocs')}</Link>
              <Link to="/about">{t('about')}</Link>
              <Link to="/terms">{t('terms')}</Link>
            </div>
          </div>
          <PayMethods />
          <a className="cr-badge" href="https://mc.gov.sa" target="_blank" rel="noopener"
             title={en ? 'Verified commercial registration — Ministry of Commerce' : 'سجل تجاري موثّق — وزارة التجارة'}>
            <svg viewBox="0 0 24 24" width="30" height="30" fill="none" stroke="currentColor" strokeWidth="1.7" aria-hidden="true">
              <path d="M12 2l7 3v6c0 4.4-3 7.9-7 9-4-1.1-7-4.6-7-9V5l7-3z" fill="rgba(31,122,84,.08)" />
              <path d="M9 12l2 2 4-4" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            <span>
              <strong>{en ? 'Verified commercial registration' : 'سجل تجاري موثّق'}</strong>
              <small dir="ltr">{en ? 'Unified No. 7041122404 · Active' : 'الرقم الموحّد 7041122404 · مؤسسة · نشط'}</small>
            </span>
          </a>
          <div className="ftr-bottom">
            <span>© {new Date().getFullYear()} رِواء الحرمين — {t('rights')}</span>
            <span className="muted">{t('cities')}</span>
          </div>
        </div>
      </footer>

      <a className="wa-float" href="https://wa.me/966531995976" target="_blank" rel="noopener" aria-label="WhatsApp" title={t('contactUs')}>
        <svg viewBox="0 0 32 32" width="30" height="30" fill="#fff" aria-hidden="true"><path d="M16.04 4C9.9 4 4.92 8.98 4.92 15.12c0 2.03.55 3.98 1.58 5.7L4.8 28l7.36-1.66a11.07 11.07 0 0 0 3.88.7h.01c6.13 0 11.11-4.98 11.11-11.12C27.16 8.98 22.18 4 16.04 4Zm0 20.3h-.01c-1.2 0-2.38-.32-3.4-.93l-.24-.14-4.37.98.93-4.26-.16-.25a9.12 9.12 0 0 1-1.4-4.84c0-5.04 4.1-9.14 9.15-9.14 2.44 0 4.74.95 6.46 2.68a9.08 9.08 0 0 1 2.68 6.47c0 5.04-4.1 9.14-9.14 9.14Zm5.02-6.84c-.27-.14-1.63-.8-1.88-.9-.25-.09-.43-.13-.62.14-.18.27-.71.9-.87 1.08-.16.18-.32.2-.59.07-.27-.14-1.16-.43-2.21-1.36-.82-.73-1.37-1.63-1.53-1.9-.16-.27-.02-.42.12-.55.12-.12.27-.32.4-.48.14-.16.18-.27.27-.46.09-.18.05-.34-.02-.48-.07-.14-.62-1.5-.85-2.05-.22-.53-.45-.46-.62-.47l-.53-.01c-.18 0-.48.07-.73.34-.25.27-.96.94-.96 2.3 0 1.36.98 2.67 1.12 2.85.14.18 1.94 2.96 4.7 4.15.66.28 1.17.45 1.57.58.66.21 1.26.18 1.73.11.53-.08 1.63-.67 1.86-1.3.23-.64.23-1.19.16-1.3-.07-.12-.25-.19-.52-.32Z"/></svg>
      </a>
    </>
  )
}
