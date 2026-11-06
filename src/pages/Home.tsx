import { Link } from 'react-router-dom'
import RawaaAssistant from '../components/RawaaAssistant'
import { useI18n } from '../lib/i18n'

export default function Home() {
  const { t } = useI18n()
  return (
    <>
      <div className="promo">
        <div><h3>{t('promoTitle')}</h3><p>{t('promoText')}</p></div>
        <Link className="btn" to="/products">{t('shopNow')}</Link>
      </div>
      <RawaaAssistant />
      <section className="hero">
        <img src="/hero.png" alt="رواء الحرمين" />
        <div>
          <div className="eyebrow">{t('heroEyebrow')}</div>
          <h1>{t('heroTitle')}</h1>
          <p className="muted">{t('heroText')}</p>
          <div style={{ display: 'flex', gap: 12, marginTop: 20, flexWrap: 'wrap' }}>
            <Link className="btn" to="/products">{t('discover')}</Link>
            <Link className="btn ghost" to="/suppliers">{t('suppliers')}</Link>
          </div>
        </div>
      </section>
      <div className="gift">
        <div><h3 style={{ margin: '0 0 6px' }}>{t('giftTitle')}</h3><p style={{ margin: 0 }}>{t('giftText')}</p></div>
        <Link className="btn" to="/gifts">{t('giftStart')}</Link>
      </div>
    </>
  )
}
