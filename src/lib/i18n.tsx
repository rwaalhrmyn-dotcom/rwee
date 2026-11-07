import { createContext, useContext, useEffect, useState, ReactNode } from 'react'

export type Lang = 'ar' | 'en' | 'ur' | 'fr' | 'id' | 'tr'
export const LANGS: { code: Lang; label: string; dir: 'rtl' | 'ltr' }[] = [
  { code: 'ar', label: 'العربية', dir: 'rtl' },
  { code: 'en', label: 'English', dir: 'ltr' },
  { code: 'ur', label: 'اردو', dir: 'rtl' },
  { code: 'fr', label: 'Français', dir: 'ltr' },
  { code: 'id', label: 'Bahasa', dir: 'ltr' },
  { code: 'tr', label: 'Türkçe', dir: 'ltr' },
]

type Dict = Record<string, string>
const T: Record<Lang, Dict> = {
  ar: {
    tagline: 'عناية تصل إلى حيث تحتاجها',
    topbar: 'منصة تجارية مختصة في توصيل المياه للمساجد والمنازل · من اختيارك، إلى باب المستفيد',
    home: 'الرئيسية', products: 'المنتجات', shopAll: 'تسوّق كل المنتجات', categories: 'الفئات',
    water: 'المياه والسقيا', quran: 'المصاحف وحواملها', supplies: 'مستلزمات المساجد', food: 'الأغذية', equipment: 'التجهيزات',
    bundles: 'الباقات والتوريد الدوري', suppliers: 'الموردون', suppliersList: 'قائمة الموردين', compare: 'مقارنة الموردين',
    joinSupplier: 'انضم كمورد', supplierPortal: 'بوابة المورد', orgsOffers: 'الجمعيات والعروض',
    orgSupply: 'توريد الجمعيات الخيرية', quote: 'طلب عرض توريد', needs: 'احتياجات الجمعية',
    gifts: 'أهدِ من تحب', loyalty: 'مكافآت رِواء', cart: 'السلة', account: 'حسابي', myAccount: 'حسابي وطلباتي',
    deliveryDocs: 'توثيق التسليم', customerLogin: 'تسجيل دخول العميل', adminPanel: 'لوحة الإدارة', menu: 'القائمة',
    heroEyebrow: '— من قلب الحرمين، إلى كل مكان', heroTitle: 'احتياجك يصل بعناية.',
    heroText: 'المياه والمصاحف ومستلزمات المساجد في تجربة واحدة واضحة. منصة تجارية مختصة في توصيل المياه للمساجد والمنازل بعناية وموثوقية.',
    discover: 'اكتشف المنتجات ←', shopNow: 'تسوّق الآن ←',
    promoTitle: 'كل ما يحتاجه المكان، يصل بعناية', promoText: 'مياه ومصاحف ومستلزمات المساجد — طلب واحد، وتوصيل موثوق للمساجد والمنازل.',
    giftTitle: 'أهدِ من تحب، بحبّ 🤍', giftText: 'أهدِ مياهاً ومصاحف ومستلزمات باسم من تحب، عطاءً يصل حيث الحاجة.',
    giftStart: 'ابدأ الإهداء ←',
    asstTitle: 'مساعد رِواء الذكي', asstSub: 'قل لنا ما تحتاجه، ودعنا نساعدك في الاختيار.',
    asstPlaceholder: 'اسأل عن المياه، المصاحف، أو متابعة طلبك…', ask: 'اسأل ←', go: 'اذهب ←',
    ftrAbout: 'منصة تجارية مختصة في توصيل المياه للمساجد والمنازل، مع المصاحف ومستلزمات المساجد، بعناية وموثوقية.',
    ftrProducts: 'المنتجات', ftrSuppliersOrgs: 'الموردون', ftrAccount: 'حسابك',
    myOrders: 'طلباتي', terms: 'السياسة والخصوصية', rights: 'جميع الحقوق محفوظة', about: 'عن المنصة',
    cities: 'منصة تجارية · بياناتك تبقى خاصة',
  },
  en: {
    tagline: 'Care delivered where you need it',
    topbar: 'A commercial platform specialized in delivering water to mosques and homes · from your choice to the door',
    home: 'Home', products: 'Products', shopAll: 'Shop all products', categories: 'Categories',
    water: 'Water', quran: 'Qurans & stands', supplies: 'Mosque supplies', food: 'Food', equipment: 'Equipment',
    bundles: 'Bundles & recurring supply', suppliers: 'Suppliers', suppliersList: 'Supplier list', compare: 'Compare suppliers',
    joinSupplier: 'Join as supplier', supplierPortal: 'Supplier portal', orgsOffers: 'Charities & offers',
    orgSupply: 'Charity supply', quote: 'Request a quote', needs: 'Facility needs',
    gifts: 'Gift to loved ones', loyalty: 'Rawaa rewards', cart: 'Cart', account: 'Account', myAccount: 'My account & orders',
    deliveryDocs: 'Delivery proof', customerLogin: 'Customer login', adminPanel: 'Admin panel', menu: 'Menu',
    heroEyebrow: '— From the heart of the Haramain, everywhere', heroTitle: 'Your needs, delivered with care.',
    heroText: 'Water, Qurans and mosque supplies in one clear experience. A commercial platform specialized in delivering water to mosques and homes — with care and reliability.',
    discover: 'Discover products →', shopNow: 'Shop now →',
    promoTitle: 'Everything the place needs, delivered with care', promoText: 'Water, Qurans and mosque supplies — one order, trusted delivery to mosques and homes.',
    giftTitle: 'Give with love, to those you love 🤍', giftText: 'Gift water, Qurans and supplies in a loved one’s name, or make it an ongoing charity.',
    giftStart: 'Start gifting →',
    asstTitle: 'Rawaa smart assistant', asstSub: 'Tell us what you need and we’ll help you choose.',
    asstPlaceholder: 'Ask about water, Qurans, or track your order…', ask: 'Ask →', go: 'Go →',
    ftrAbout: 'A commercial platform specialized in delivering water to mosques and homes, alongside Qurans and mosque supplies, with care and reliability.',
    ftrProducts: 'Products', ftrSuppliersOrgs: 'Suppliers', ftrAccount: 'Your account',
    myOrders: 'My orders', terms: 'Policy & privacy', rights: 'All rights reserved', about: 'About',
    cities: 'A commercial platform · your data stays private',
  },
  ur: {
    tagline: 'دیکھ بھال، جہاں آپ کو ضرورت ہو', topbar: 'مساجد اور گھروں تک پانی کی ترسیل میں مختص تجارتی پلیٹ فارم · آپ کے انتخاب سے دروازے تک',
    home: 'ہوم', products: 'مصنوعات', shopAll: 'تمام مصنوعات', categories: 'اقسام',
    water: 'پانی', quran: 'قرآن و ریحل', supplies: 'مسجد سامان', food: 'غذا', equipment: 'آلات',
    bundles: 'پیکجز و باقاعدہ سپلائی', suppliers: 'سپلائرز', suppliersList: 'سپلائرز کی فہرست', compare: 'سپلائرز کا موازنہ',
    joinSupplier: 'سپلائر بنیں', supplierPortal: 'سپلائر پورٹل', orgsOffers: 'ادارے و پیشکشیں',
    orgSupply: 'فلاحی سپلائی', quote: 'قیمت درخواست', needs: 'ادارے کی ضروریات',
    gifts: 'تحفہ دیں', loyalty: 'رِواء انعامات', cart: 'ٹوکری', account: 'اکاؤنٹ', myAccount: 'میرا اکاؤنٹ و آرڈرز',
    deliveryDocs: 'ترسیل ثبوت', customerLogin: 'کسٹمر لاگ ان', adminPanel: 'ایڈمن پینل', menu: 'مینو',
    heroEyebrow: '— حرمین کے دل سے، ہر جگہ', heroTitle: 'آپ کی ضروریات، خیال سے پہنچیں۔',
    heroText: 'پانی، قرآن اور مسجد کا سامان ایک واضح خریداری میں۔',
    discover: 'مصنوعات دیکھیں →', shopNow: 'ابھی خریدیں →',
    promoTitle: 'ہر ضرورت، خیال سے پہنچے', promoText: 'پانی، قرآن اور مسجد سامان — ایک آرڈر، چار شہروں تک قابل اعتماد ترسیل۔',
    giftTitle: 'محبت سے دیں 🤍', giftText: 'اپنے پیاروں کے نام پر تحفہ دیں یا صدقہ جاریہ بنائیں۔', giftStart: 'تحفہ شروع کریں →',
    asstTitle: 'رِواء اسمارٹ اسسٹنٹ', asstSub: 'بتائیں آپ کو کیا چاہیے، ہم مدد کریں گے۔',
    asstPlaceholder: 'پانی، قرآن یا آرڈر ٹریک کے بارے میں پوچھیں…', ask: 'پوچھیں →', go: 'جائیں →',
    ftrAbout: 'ایک تجارتی پلیٹ فارم جو مساجد اور گھروں تک پانی، قرآن اور مسجد کا سامان خیال سے پہنچاتا ہے۔',
    ftrProducts: 'مصنوعات', ftrSuppliersOrgs: 'سپلائرز', ftrAccount: 'آپ کا اکاؤنٹ',
    myOrders: 'میرے آرڈرز', terms: 'پالیسی و رازداری', rights: 'جملہ حقوق محفوظ ہیں', about: 'ادارے کے بارے میں',
    cities: 'تجارتی پلیٹ فارم · آپ کا ڈیٹا محفوظ',
  },
  fr: {
    tagline: 'Le soin livré où vous en avez besoin', topbar: 'Une plateforme commerciale spécialisée dans la livraison d’eau aux mosquées et aux foyers · de votre choix à la porte',
    home: 'Accueil', products: 'Produits', shopAll: 'Tous les produits', categories: 'Catégories',
    water: 'Eau', quran: 'Corans et porte-Corans', supplies: 'Fournitures de mosquée', food: 'Alimentation', equipment: 'Équipement',
    bundles: 'Offres et appro. récurrent', suppliers: 'Fournisseurs', suppliersList: 'Liste des fournisseurs', compare: 'Comparer',
    joinSupplier: 'Devenir fournisseur', supplierPortal: 'Portail fournisseur', orgsOffers: 'Associations & offres',
    orgSupply: 'Appro. associations', quote: 'Demander un devis', needs: 'Besoins de l’établissement',
    gifts: 'Offrir à vos proches', loyalty: 'Récompenses Rawaa', cart: 'Panier', account: 'Compte', myAccount: 'Mon compte & commandes',
    deliveryDocs: 'Preuve de livraison', customerLogin: 'Connexion client', adminPanel: 'Admin', menu: 'Menu',
    heroEyebrow: '— Du cœur des Haramain, partout', heroTitle: 'Vos besoins, livrés avec soin.',
    heroText: 'Eau, Corans et fournitures de mosquée en un seul achat clair.',
    discover: 'Découvrir →', shopNow: 'Acheter →',
    promoTitle: 'Tout ce qu’il faut, livré avec soin', promoText: 'Eau, Corans et fournitures — une commande, livraison fiable.',
    giftTitle: 'Offrez avec amour 🤍', giftText: 'Offrez au nom d’un proche ou faites-en une aumône continue.', giftStart: 'Offrir →',
    asstTitle: 'Assistant Rawaa', asstSub: 'Dites-nous ce qu’il vous faut.',
    asstPlaceholder: 'Eau, Corans, suivi de commande…', ask: 'Demander →', go: 'Aller →',
    ftrAbout: 'Une plateforme commerciale spécialisée dans la livraison d’eau aux mosquées et aux foyers, avec Corans et fournitures de mosquée, livrés avec soin.',
    ftrProducts: 'Produits', ftrSuppliersOrgs: 'Fournisseurs', ftrAccount: 'Votre compte',
    myOrders: 'Mes commandes', terms: 'Politique & confidentialité', rights: 'Tous droits réservés', about: 'À propos',
    cities: 'Plateforme commerciale · vos données restent privées',
  },
  id: {
    tagline: 'Perhatian diantar ke tempat Anda', topbar: 'Platform komersial khusus pengantaran air ke masjid dan rumah · dari pilihan Anda ke pintu',
    home: 'Beranda', products: 'Produk', shopAll: 'Semua produk', categories: 'Kategori',
    water: 'Air', quran: 'Alquran & rehal', supplies: 'Perlengkapan masjid', food: 'Makanan', equipment: 'Peralatan',
    bundles: 'Paket & pasokan berkala', suppliers: 'Pemasok', suppliersList: 'Daftar pemasok', compare: 'Bandingkan',
    joinSupplier: 'Gabung sebagai pemasok', supplierPortal: 'Portal pemasok', orgsOffers: 'Lembaga & penawaran',
    orgSupply: 'Pasokan lembaga', quote: 'Minta penawaran', needs: 'Kebutuhan lembaga',
    gifts: 'Hadiah untuk orang tersayang', loyalty: 'Hadiah Rawaa', cart: 'Keranjang', account: 'Akun', myAccount: 'Akun & pesanan',
    deliveryDocs: 'Bukti pengiriman', customerLogin: 'Masuk pelanggan', adminPanel: 'Admin', menu: 'Menu',
    heroEyebrow: '— Dari jantung Haramain, ke mana saja', heroTitle: 'Kebutuhan Anda, diantar dengan perhatian.',
    heroText: 'Air, Alquran, dan perlengkapan masjid dalam satu pembelian jelas.',
    discover: 'Lihat produk →', shopNow: 'Belanja →',
    promoTitle: 'Semua kebutuhan, diantar', promoText: 'Air, Alquran, perlengkapan — satu pesanan, pengiriman tepercaya.',
    giftTitle: 'Beri dengan cinta 🤍', giftText: 'Hadiahkan atas nama orang tersayang atau jadikan sedekah jariah.', giftStart: 'Mulai →',
    asstTitle: 'Asisten Rawaa', asstSub: 'Beri tahu kebutuhan Anda.',
    asstPlaceholder: 'Tanya air, Alquran, atau lacak pesanan…', ask: 'Tanya →', go: 'Pergi →',
    ftrAbout: 'Platform komersial khusus pengantaran air ke masjid dan rumah, beserta Alquran dan perlengkapan masjid, dengan perhatian.',
    ftrProducts: 'Produk', ftrSuppliersOrgs: 'Pemasok', ftrAccount: 'Akun Anda',
    myOrders: 'Pesanan saya', terms: 'Kebijakan & privasi', rights: 'Hak cipta dilindungi', about: 'Tentang',
    cities: 'Platform komersial · data Anda tetap privat',
  },
  tr: {
    tagline: 'İhtiyacınız olan yere ulaşan özen', topbar: 'Camilere ve evlere su teslimatında uzman ticari bir platform · seçiminizden kapıya',
    home: 'Ana sayfa', products: 'Ürünler', shopAll: 'Tüm ürünler', categories: 'Kategoriler',
    water: 'Su', quran: 'Kuran ve rahleler', supplies: 'Cami malzemeleri', food: 'Gıda', equipment: 'Ekipman',
    bundles: 'Paketler ve düzenli tedarik', suppliers: 'Tedarikçiler', suppliersList: 'Tedarikçi listesi', compare: 'Karşılaştır',
    joinSupplier: 'Tedarikçi ol', supplierPortal: 'Tedarikçi portalı', orgsOffers: 'Dernekler ve teklifler',
    orgSupply: 'Dernek tedariği', quote: 'Teklif iste', needs: 'Kurum ihtiyaçları',
    gifts: 'Sevdiklerinize hediye', loyalty: 'Rawaa ödülleri', cart: 'Sepet', account: 'Hesap', myAccount: 'Hesabım ve siparişler',
    deliveryDocs: 'Teslim kanıtı', customerLogin: 'Müşteri girişi', adminPanel: 'Yönetim', menu: 'Menü',
    heroEyebrow: '— Haremeyn’in kalbinden, her yere', heroTitle: 'İhtiyaçlarınız özenle ulaşır.',
    heroText: 'Su, Kuran ve cami malzemeleri tek ve net bir alışverişte.',
    discover: 'Ürünleri keşfet →', shopNow: 'Alışveriş →',
    promoTitle: 'Her ihtiyaç, özenle ulaşır', promoText: 'Su, Kuran ve malzemeler — tek sipariş, güvenilir teslimat.',
    giftTitle: 'Sevgiyle verin 🤍', giftText: 'Sevdiğiniz birinin adına hediye edin veya sadaka-i cariye yapın.', giftStart: 'Başla →',
    asstTitle: 'Rawaa akıllı asistan', asstSub: 'Neye ihtiyacınız olduğunu söyleyin.',
    asstPlaceholder: 'Su, Kuran veya sipariş takibi sorun…', ask: 'Sor →', go: 'Git →',
    ftrAbout: 'Camilere ve evlere su teslimatında uzman, Kuran ve cami malzemeleri de sunan ticari bir platform.',
    ftrProducts: 'Ürünler', ftrSuppliersOrgs: 'Tedarikçiler', ftrAccount: 'Hesabınız',
    myOrders: 'Siparişlerim', terms: 'Politika ve gizlilik', rights: 'Tüm hakları saklıdır', about: 'Hakkında',
    cities: 'Ticari platform · verileriniz gizli kalır',
  },
}

const Ctx = createContext<{ lang: Lang; setLang: (l: Lang) => void; t: (k: string) => string } | null>(null)

export function LanguageProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>(() => {
    try { return (localStorage.getItem('riwa_lang') as Lang) || 'ar' } catch { return 'ar' }
  })
  const dir = LANGS.find(l => l.code === lang)?.dir || 'rtl'
  useEffect(() => {
    document.documentElement.lang = lang
    document.documentElement.dir = dir
    try { localStorage.setItem('riwa_lang', lang) } catch {}
  }, [lang, dir])
  const setLang = (l: Lang) => setLangState(l)
  const t = (k: string) => T[lang][k] ?? T.ar[k] ?? k
  return <Ctx.Provider value={{ lang, setLang, t }}>{children}</Ctx.Provider>
}
export const useI18n = () => {
  const c = useContext(Ctx); if (!c) throw new Error('LanguageProvider missing'); return c
}
