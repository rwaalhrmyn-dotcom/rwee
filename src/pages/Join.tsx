import { Link } from 'react-router-dom'
import { useI18n } from '../lib/i18n'

export default function Join() {
  const { t } = useI18n()
  return (
    <section style={{ padding: '32px 0' }}>
      <h2 style={{ color: 'var(--green)' }}>{t('home') === 'Home' ? 'Join Rawaa' : 'انضم إلى رِواء الحرمين'}</h2>
      <p className="muted">{t('home') === 'Home' ? 'Choose how you want to register.' : 'اختر طريقة تسجيلك: كعميل، أو كمورد / جمعية.'}</p>
      <div className="grid" style={{ gridTemplateColumns: 'repeat(auto-fit,minmax(280px,1fr))', marginTop: 20 }}>
        <div className="card">
          <div style={{ fontSize: 30 }}>👤</div>
          <h3 style={{ color: 'var(--green)' }}>{t('home') === 'Home' ? 'As a customer' : 'كعميل'}</h3>
          <p className="muted">{t('home') === 'Home' ? 'Shop, track orders and earn rewards. Your profile is saved securely.' : 'تسوّق وتابع طلباتك واكسب المكافآت. تُحفظ بياناتك بأمان في حسابك.'}</p>
          <Link className="btn" to="/customer/login">{t('customerLogin')} ←</Link>
        </div>
        <div className="card">
          <div style={{ fontSize: 30 }}>🏢</div>
          <h3 style={{ color: 'var(--green)' }}>{t('home') === 'Home' ? 'As a supplier' : 'كمورد'}</h3>
          <p className="muted">{t('home') === 'Home' ? 'Official establishment, commercial registration and documents — reviewed before activation.' : 'منشأة رسمية وسجل تجاري ومستندات — تُراجع قبل التفعيل.'}</p>
          <Link className="btn" to="/supplier/register">{t('joinSupplier')} ←</Link>
        </div>
        <div className="card">
          <div style={{ fontSize: 30 }}>🤝</div>
          <h3 style={{ color: 'var(--green)' }}>{t('home') === 'Home' ? 'Charity / organization' : 'جمعية / منشأة'}</h3>
          <p className="muted">{t('home') === 'Home' ? 'Request a supply quote or publish your facility needs.' : 'اطلب عرض توريد أو انشر احتياجات جمعيتك.'}</p>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <Link className="btn" to="/business">{t('quote')} ←</Link>
            <Link className="btn ghost" to="/needs">{t('needs')}</Link>
          </div>
        </div>
      </div>
    </section>
  )
}
