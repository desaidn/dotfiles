export const webPalette = {
  accent: '#ffb86c',
  enabled: true,
}

export function formatColor(input) {
  return `color:${input}`
}

console.log(formatColor(webPalette.accent))
