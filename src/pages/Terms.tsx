import { useI18n } from '../lib/i18n'

export default function Terms() {
  const { t } = useI18n()
  const en = t('home') === 'Home'
  if (en) return (
    <section style={{ padding: '32px 0', maxWidth: 820 }}>
      <h2 style={{ color: 'var(--green)' }}>Usage Policy, Privacy & Rights</h2>
      <div className="card" style={{ lineHeight: 2 }}>
        <p className="muted">رِواء الحرمين is a commercial platform for selling and delivering water and mosque supplies. This policy is governed by the laws and regulations of the Kingdom of Saudi Arabia.</p>
        <h3 style={{ color: 'var(--green)' }}>1. Nature of the platform</h3>
        <p>A commercial platform specialized in selling and delivering water to mosques and homes, alongside Qurans and mosque supplies.</p>
        <h3 style={{ color: 'var(--green)' }}>2. Privacy of personal data</h3>
        <p>We collect only the data necessary to fulfil orders and delivery (name, phone, city, address). Data is processed in accordance with the Saudi Personal Data Protection Law (PDPL) and its regulations, kept confidential, and never sold or shared except with parties required to fulfil the order, or when required by a competent authority.</p>
        <h3 style={{ color: 'var(--green)' }}>3. Acceptable use</h3>
        <p>The platform is used lawfully and in good faith. Suppliers warrant the validity of their establishment, commercial registration and documents; applications remain under review until approved.</p>
        <h3 style={{ color: 'var(--green)' }}>4. Intellectual property & rights</h3>
        <p>All content, trademarks and rights are protected under the applicable laws of the Kingdom of Saudi Arabia.</p>
        <h3 style={{ color: 'var(--green)' }}>5. Governing law & disputes</h3>
        <p>These terms are subject to the laws of the Kingdom of Saudi Arabia, and any dispute falls under the jurisdiction of the competent Saudi authorities.</p>
        <h3 style={{ color: 'var(--green)' }}>6. Your rights</h3>
        <p>You may access, correct or request deletion of your personal data, in line with the PDPL.</p>
      </div>
    </section>
  )
  return (
    <section style={{ padding: '32px 0', maxWidth: 820 }}>
      <h2 style={{ color: 'var(--green)' }}>سياسة الاستخدام والخصوصية وضمان الحقوق</h2>
      <div className="card" style={{ lineHeight: 2 }}>
        <p className="muted">رِواء الحرمين منصة تجارية متخصصة في بيع وتوصيل المياه ومستلزمات المساجد. تخضع هذه السياسة لأنظمة ولوائح المملكة العربية السعودية.</p>
        <h3 style={{ color: 'var(--green)' }}>١. طبيعة المنصة</h3>
        <p>منصة <strong>تجارية</strong> متخصصة في بيع وتوصيل المياه للمساجد والمنازل، مع المصاحف ومستلزمات المساجد.</p>
        <h3 style={{ color: 'var(--green)' }}>٢. خصوصية البيانات الشخصية</h3>
        <p>نجمع فقط البيانات اللازمة لتنفيذ الطلبات والتوصيل (الاسم، الجوال، المدينة، العنوان). تُعالَج البيانات وفق <strong>نظام حماية البيانات الشخصية</strong> في المملكة ولوائحه التنفيذية، وتبقى سرّية، ولا تُباع ولا تُشارك إلا مع الأطراف اللازمة لتنفيذ الطلب، أو عند طلب جهة مختصة نظاماً.</p>
        <h3 style={{ color: 'var(--green)' }}>٣. الاستخدام المقبول</h3>
        <p>تُستخدم المنصة بما يوافق الأنظمة وبحسن نية. يقرّ المورد بصحة بيانات منشأته وسجلّه التجاري ومستنداته، وتبقى طلبات الانضمام قيد المراجعة حتى اعتمادها.</p>
        <h3 style={{ color: 'var(--green)' }}>٤. الملكية الفكرية وضمان الحقوق</h3>
        <p>جميع المحتويات والعلامات والحقوق محفوظة ومكفولة بموجب الأنظمة المعمول بها في المملكة العربية السعودية.</p>
        <h3 style={{ color: 'var(--green)' }}>٥. النظام الواجب التطبيق والنزاعات</h3>
        <p>تخضع هذه الشروط لأنظمة المملكة العربية السعودية، وأي نزاع يكون من اختصاص الجهات السعودية المختصة.</p>
        <h3 style={{ color: 'var(--green)' }}>٦. حقوقك</h3>
        <p>يحق لك الوصول إلى بياناتك الشخصية أو تصحيحها أو طلب حذفها، وفق نظام حماية البيانات الشخصية.</p>
      </div>
    </section>
  )
}
