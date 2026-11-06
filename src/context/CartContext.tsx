import { createContext, useContext, useEffect, useState, ReactNode } from 'react'

export type CartItem = { id: string; name: string; price_halalas: number; qty: number }
type Ctx = {
  items: CartItem[]
  add: (i: Omit<CartItem, 'qty'>) => void
  remove: (id: string) => void
  clear: () => void
  total: number
}
const CartCtx = createContext<Ctx | null>(null)

export function CartProvider({ children }: { children: ReactNode }) {
  const [items, setItems] = useState<CartItem[]>(() => {
    try { return JSON.parse(localStorage.getItem('riwa_cart') || '[]') } catch { return [] }
  })
  useEffect(() => { try { localStorage.setItem('riwa_cart', JSON.stringify(items)) } catch {} }, [items])
  const add = (i: Omit<CartItem, 'qty'>) =>
    setItems(p => { const e = p.find(x => x.id === i.id); return e ? p.map(x => x.id === i.id ? { ...x, qty: x.qty + 1 } : x) : [...p, { ...i, qty: 1 }] })
  const remove = (id: string) => setItems(p => p.filter(x => x.id !== id))
  const clear = () => setItems([])
  const total = items.reduce((s, x) => s + x.price_halalas * x.qty, 0)
  return <CartCtx.Provider value={{ items, add, remove, clear, total }}>{children}</CartCtx.Provider>
}
export const useCart = () => {
  const c = useContext(CartCtx); if (!c) throw new Error('CartProvider missing'); return c
}
