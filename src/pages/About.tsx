import { useI18n } from '../lib/i18n'

export default function About() {
  const { t } = useI18n()
  const en = t('home') === 'Home'
  return (
    <section style={{ padding: '32px 0', maxWidth: 820 }}>
      <div className="eyebrow">{en ? '— About the platform' : '— عن المنصة'}</div>
      <h2 style={{ color: 'var(--green)' }}>{en ? 'A non-profit platform' : 'منصة غير ربحية'}</h2>
      <div className="card" style={{ lineHeight: 2 }}>
        {en ? (
          <>
            <p><strong>رِواء الحرمين</strong> is a <strong>non-profit platform</strong> dedicated to providing water, Qurans and mosque supplies and delivering them with care — in service of the houses of Allah and their visitors.</p>
            <p>We do not operate for commercial profit. Our goal is to make giving easy, trustworthy and transparent: connecting generous people, approved suppliers and charitable organizations within one clear experience.</p>
            <p>Every order, gift and ongoing contribution is handled with care from choice to delivery, and your data is kept private.</p>
          </>
        ) : (
          <>
            <p><strong>رِواء الحرمين</strong> منصة <strong>غير ربحية</strong> تُعنى بتوفير المياه والمصاحف ومستلزمات المساجد وإيصالها بعناية، خدمةً لبيوت الله وقاصديها.</p>
            <p>لا تعمل المنصة بهدف الربح التجاري؛ غايتها تيسير العطاء بشفافية وموثوقية، بوصل أهل الخير بالموردين المعتمدين والجمعيات الخيرية في تجربة واحدة واضحة.</p>
            <p>كل طلب وإهداء وتوريد مستمر يُدار بعناية من الاختيار إلى التسليم، مع الحفاظ على خصوصية بياناتك.</p>
          </>
        )}
      </div>
    </section>
  )
}
