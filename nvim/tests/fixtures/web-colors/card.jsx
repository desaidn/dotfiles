export function ColorCard({ label, color }) {
  const className = color === 'peach' ? 'accent' : 'muted'

  return (
    <section data-color={color} className={className}>
      <h1>{label}</h1>
      <span aria-hidden="true">swatch</span>
    </section>
  )
}
