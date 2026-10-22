import { createInertiaApp, router, type ResolvedComponent } from '@inertiajs/react'
import { StrictMode, createElement } from 'react'
import { createRoot } from 'react-dom/client'
import { ThemeProvider } from 'next-themes'

import { Toaster } from '@/components/ui/sonner'
import { setLocale } from '@/lib/i18n'

// Disable the error modal - errors handled via flash messages.
// Inertia v3 renamed the event that guards the modal from 'invalid' to
// 'httpException'; the old name is never fired.
router.on('httpException', (event) => {
  event.preventDefault()
})

void createInertiaApp({
  // Set default page title
  // see https://inertia-rails.dev/guide/title-and-meta
  //
  // title: title => title ? `${title} - App` : 'App',

  // Disable progress bar
  //
  // see https://inertia-rails.dev/guide/progress-indicators
  // progress: false,

  resolve: (name) => {
    const pages = import.meta.glob<{default: ResolvedComponent}>('../pages/**/*.tsx', {
      eager: true,
    })
    const page = pages[`../pages/${name}.tsx`]
    if (!page) {
      console.error(`Missing Inertia page component: '${name}.tsx'`)
    }

    // To use a default layout, import the Layout component
    // and use the following line.
    // see https://inertia-rails.dev/guide/pages#default-layouts
    //
    // page.default.layout ||= (page: ReactNode) => (<Layout>{page}</Layout>)

    return page
  },

  setup({ el, App, props }) {
    if (!el) return
    setLocale(props.initialPage.props.locale)

    createRoot(el).render(
      <StrictMode>
        <ThemeProvider attribute="class" defaultTheme="dark" enableSystem={false}>
          <App {...props}>
            {/* The UI language comes with every page (see ApplicationController#
                inertia_share locale); set it before the page renders so `t()`
                calls in the page and its children all use it. */}
            {({ Component, props: pageProps, key }) => {
              setLocale(pageProps.locale)
              return createElement(Component, { key, ...pageProps })
            }}
          </App>
          <Toaster />
        </ThemeProvider>
      </StrictMode>
    )
  },

  defaults: {
    form: {
      forceIndicesArrayFormatInFormData: false,
    },
    // The v2 `future` flags (script-element initial page, data-inertia head
    // attribute, preserveEqualProps, …) are built-in behaviour in v3.
  },
}).catch((error) => {
  // This ensures this entrypoint is only loaded on Inertia pages
  // by checking for the presence of the root element (#app by default).
  // Feel free to remove this `catch` if you don't need it.
  if (document.getElementById("app")) {
    throw error
  } else {
    console.error(
      "Missing root element.\n\n" +
      "If you see this error, it probably means you loaded Inertia.js on non-Inertia pages.\n" +
      'Consider moving <%= vite_typescript_tag "inertia.tsx" %> to the Inertia-specific layout instead.',
    )
  }
})
