import { useI18n } from '../lib/i18n'

export default function About() {
  const { t } = useI18n()
  const en = t('home') === 'Home'
  return (
    <section style={{ padding: '32px 0', maxWidth: 820 }}>
      <div className="eyebrow">{en ? '— About the platform' : '— عن المنصة'}</div>
      <h2 style={{ color: 'var(--green)' }}>{en ? 'A commercial water-delivery platform' : 'منصة تجارية لتوصيل المياه'}</h2>
      <div className="card" style={{ lineHeight: 2 }}>
        {en ? (
          <>
            <p><strong>رِواء الحرمين</strong> is a <strong>commercial platform specialized in delivering water to mosques and homes</strong>, alongside Qurans and mosque supplies, delivered with care and reliability.</p>
            <p>Our goal is to make ordering easy, trustworthy and transparent: connecting customers, mosques and homes with approved suppliers within one clear experience.</p>
            <p>Every order, gift and recurring supply is handled with care from choice to delivery, and your data is kept private.</p>
          </>
        ) : (
          <>
            <p><strong>رِواء الحرمين</strong> <strong>منصة تجارية مختصة في توصيل المياه للمساجد والمنازل</strong>، مع المصاحف ومستلزمات المساجد، تصل بعناية وموثوقية.</p>
            <p>غايتها تيسير الطلب بشفافية وموثوقية، بوصل العملاء والمساجد والمنازل بالموردين المعتمدين في تجربة واحدة واضحة.</p>
            <p>كل طلب وإهداء وتوريد مستمر يُدار بعناية من الاختيار إلى التسليم، مع الحفاظ على خصوصية بياناتك.</p>
          </>
        )}
      </div>
    </section>
  )
}
