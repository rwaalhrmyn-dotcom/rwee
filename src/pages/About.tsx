import { useI18n } from '../lib/i18n'

export default function About() {
  const { t } = useI18n()
  const en = t('home') === 'Home'
  return (
    <section style={{ padding: '32px 0', maxWidth: 820 }}>
      <div className="eyebrow">{en ? '— Who we are' : '— من نحن'}</div>
      <h2 style={{ color: 'var(--green)' }}>{en ? 'Who we are' : 'من نحن'}</h2>
      <div className="card" style={{ lineHeight: 2 }}>
        {en ? (
          <>
            <p>We are a platform that provides the essentials for mosques and those who fast — from Qurans, water, tissues and foldable chairs to iftar and suhoor meals — with a focus on quality, comfort and ease of delivery.</p>
            <p>Our goal is to simplify your daily life and bring everything you need together in one place.</p>
          </>
        ) : (
          <>
            <p>نحن منصة تقدّم المستلزمات الأساسية للمساجد والصائمين — من المصاحف والمياه والمناديل والكراسي القابلة للطيّ، إلى وجبات الإفطار والسحور — مع التركيز على الجودة والراحة وسهولة التوصيل.</p>
            <p>هدفنا تسهيل حياتك اليومية وتوفير كل ما تحتاجه في مكان واحد.</p>
          </>
        )}
      </div>
    </section>
  )
}
