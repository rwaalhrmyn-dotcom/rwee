import { useEffect } from 'react'
export function useSeo(title: string, description?: string) {
  useEffect(() => {
    const full = `${title} | رِواء الحرمين`
    document.title = full
    if (description) {
      let m = document.querySelector('meta[name="description"]')
      if (!m) { m = document.createElement('meta'); m.setAttribute('name', 'description'); document.head.appendChild(m) }
      m.setAttribute('content', description)
    }
  }, [title, description])
}
