type ColorCardProps = {
  label: string
  color: string
}

function ColorSwatch({ color }: { color: string }) {
  return <span data-swatch={color}>swatch</span>
}

export function ColorCard({ label, color }: ColorCardProps) {
  const className = color === 'peach' ? 'accent' : 'muted'

  return (
    <section data-color={color} className={className}>
      <h1>{label}</h1>
      <ColorSwatch color={color} />
    </section>
  )
}
