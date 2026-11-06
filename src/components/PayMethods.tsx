export default function PayMethods() {
  return (
    <div className="paybar">
      <span className="lbl">طرق الدفع:</span>
      <span className="payicon mada">mada <b>مدى</b></span>
      <span className="payicon visa">VISA</span>
      <span className="payicon mc">
        <svg viewBox="0 0 40 24" aria-label="Mastercard"><circle cx="15" cy="12" r="9" fill="#EB001B"/><circle cx="25" cy="12" r="9" fill="#F79E1B"/><path d="M20 5.5a9 9 0 0 0 0 13 9 9 0 0 0 0-13z" fill="#FF5F00"/></svg>
      </span>
      <span className="payicon apple">
        <svg viewBox="0 0 14 17" aria-hidden="true" style={{height:14,marginInlineEnd:4}}><path fill="#000" d="M11.2 9c0-1.6 1.3-2.4 1.4-2.4-.8-1.1-2-1.3-2.4-1.3-1-.1-2 .6-2.5.6s-1.3-.6-2.2-.6C4 5.3 3 6 2.4 7.1 1.2 9.3 2.1 12.6 3.3 14.4c.6.9 1.3 1.9 2.2 1.8.9 0 1.2-.6 2.3-.6s1.4.6 2.3.6c.9 0 1.5-.9 2.1-1.8.4-.6.6-1 .9-1.7-2.3-.9-2.2-3.4-2.2-3.5zM9.6 3.9c.5-.6.8-1.4.7-2.3-.7 0-1.5.5-2 1-.4.5-.8 1.3-.7 2.1.8.1 1.6-.4 2-.8z"/></svg>Pay
      </span>
      <span className="payicon tap">Tap <span style={{color:'var(--muted)',fontWeight:400,fontSize:11}}>الدفع الآمن</span></span>
    </div>
  )
}
