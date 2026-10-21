export type Flash = {
  notice?: string
  alert?: string
}

export type SharedProps = {
  flash: Flash
  // UI language: the user's choice, else the browser's (Accept-Language), else English.
  locale: 'en' | 'fr'
}
