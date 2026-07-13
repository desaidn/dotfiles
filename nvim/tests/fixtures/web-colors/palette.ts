export interface WebPalette {
  accent: string
  enabled?: boolean
}

export const webPalette: WebPalette = {
  accent: '#ffb86c',
  enabled: true,
}

export function formatColor(input: string): string {
  return `color:${input}`
}

console.log(formatColor(webPalette.accent))
