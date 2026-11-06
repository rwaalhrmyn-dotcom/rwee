import { GA_ID } from './config'
export function initGA() {
  if (!GA_ID || typeof document === 'undefined') return
  if (document.getElementById('ga-src')) return
  const s = document.createElement('script')
  s.id = 'ga-src'; s.async = true
  s.src = `https://www.googletagmanager.com/gtag/js?id=${GA_ID}`
  document.head.appendChild(s)
  const w = window as any
  w.dataLayer = w.dataLayer || []
  function gtag(...args: any[]) { w.dataLayer.push(args) }
  w.gtag = gtag
  gtag('js', new Date())
  gtag('config', GA_ID)
}
