import { useState } from 'react'
import { Link, NavLink, Outlet } from 'react-router-dom'
import { useCart } from '../context/CartContext'
import { useI18n, LANGS } from '../lib/i18n'
import PayMethods from './PayMethods'

export default function Layout() {
  const { items } = useCart()
  const count = items.reduce((s, i) => s + i.qty, 0)
  const { t, lang, setLang } = useI18n()
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
              <div className="item">
                <button>{t('orgsOffers')} <span className="caret">▾</span></button>
                <div className="drop">
                  <Link to="/business">{t('orgSupply')}</Link>
                  <Link to="/business">{t('quote')}</Link>
                  <Link to="/needs">{t('needs')}</Link>
                  <div className="sep" /><Link to="/bundles">{t('bundles')}</Link>
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
                  <Link to="/admin">{t('adminPanel')}</Link>
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
            <div className="lbl">{t('orgsOffers')}</div>
            <NavLink to="/business">{t('orgSupply')}</NavLink>
            <NavLink to="/needs">{t('needs')}</NavLink>
            <div className="lbl">{t('account')}</div>
            <NavLink to="/gifts">{t('gifts')}</NavLink>
            <NavLink to="/loyalty">{t('loyalty')}</NavLink>
            <NavLink to="/customer">{t('myAccount')}</NavLink>
            <NavLink to="/delivery">{t('deliveryDocs')}</NavLink>
            <NavLink to="/supplier">{t('supplierPortal')}</NavLink>
            <NavLink to="/admin">{t('adminPanel')}</NavLink>
          </div>
        </div>
      </header>

      <main className="container"><Outlet /></main>

      <footer className="footer">
        <div className="container">
          <div className="ftr-grid">
            <div>
              <div className="brand" style={{ marginBottom: 8 }}>رِواء الحرمين</div>
              <p className="muted" style={{ margin: 0, maxWidth: 320 }}>{t('ftrAbout')}</p>
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
              <Link to="/business">{t('orgSupply')}</Link>
              <Link to="/needs">{t('needs')}</Link>
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
          <div className="ftr-bottom">
            <span>© {new Date().getFullYear()} رِواء الحرمين — {t('rights')}</span>
            <span className="muted">{t('cities')}</span>
          </div>
        </div>
      </footer>
    </>
  )
}
