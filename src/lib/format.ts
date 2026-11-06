export const sar = (halalas: number) =>
  new Intl.NumberFormat('ar-SA', { style: 'currency', currency: 'SAR' }).format((halalas || 0) / 100)
export const CATEGORIES: Record<string, string> = {
  water: 'مياه', quran: 'مصاحف', supplies: 'مستلزمات', food: 'أغذية', equipment: 'تجهيزات',
}
export const CITIES: Record<string, string> = { makkah: 'مكة المكرمة', madinah: 'المدينة المنورة' }
