import { useEffect, useRef } from 'react'
import { MAPS_KEY } from '../lib/config'

let loading: Promise<void> | null = null
function loadMaps(): Promise<void> {
  if (!MAPS_KEY) return Promise.reject(new Error('no key'))
  if ((window as any).google?.maps?.places) return Promise.resolve()
  if (loading) return loading
  loading = new Promise((resolve, reject) => {
    const s = document.createElement('script')
    s.src = `https://maps.googleapis.com/maps/api/js?key=${MAPS_KEY}&libraries=places&language=ar&region=SA`
    s.async = true; s.onload = () => resolve(); s.onerror = () => reject(new Error('load failed'))
    document.head.appendChild(s)
  })
  return loading
}

export default function MapsAddress({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const ref = useRef<HTMLInputElement>(null)
  useEffect(() => {
    let ac: any
    if (MAPS_KEY && ref.current) {
      loadMaps().then(() => {
        const g = (window as any).google
        if (!g?.maps?.places || !ref.current) return
        ac = new g.maps.places.Autocomplete(ref.current, { componentRestrictions: { country: 'sa' }, fields: ['formatted_address'] })
        ac.addListener('place_changed', () => {
          const p = ac.getPlace(); if (p?.formatted_address) onChange(p.formatted_address)
        })
      }).catch(() => {})
    }
    return () => { if (ac && (window as any).google) (window as any).google.maps.event.clearInstanceListeners(ac) }
  }, [])
  return (
    <input ref={ref} value={value} onChange={e => onChange(e.target.value)} placeholder="الحي، الشارع، رقم المبنى" />
  )
}
