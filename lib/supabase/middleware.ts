import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({
    request,
  })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) => request.cookies.set(name, value))
          supabaseResponse = NextResponse.next({
            request,
          })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  const {
    data: { user },
  } = await supabase.auth.getUser()

  const pathname = request.nextUrl.pathname

  // Proteksi rute berdasarkan login
  if (!user && pathname.startsWith('/dashboard')) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    return NextResponse.redirect(url)
  }

  // Pengalihan dari auth halaman jika sudah login
  if (user && (pathname === '/login' || pathname === '/register')) {
    const url = request.nextUrl.clone()
    url.pathname = '/'
    return NextResponse.redirect(url)
  }

  // Proteksi rute berbasis role (dashboard)
  if (user && pathname.startsWith('/dashboard/')) {
    // Ambil data user dari tabel public.users
    const { data: userData } = await supabase
      .from('users')
      .select('role')
      .eq('id', user.id)
      .single()

    const role = userData?.role

    // Cek masing-masing rute
    if (pathname.startsWith('/dashboard/wakif') && role !== 'wakif') {
      return NextResponse.redirect(new URL('/', request.url))
    }
    if (pathname.startsWith('/dashboard/nazhir') && role !== 'nazhir') {
      return NextResponse.redirect(new URL('/', request.url))
    }
    if (pathname.startsWith('/dashboard/mitra') && role !== 'mitra_pelaksana') {
      return NextResponse.redirect(new URL('/', request.url))
    }
    if (pathname.startsWith('/dashboard/admin') && role !== 'admin') {
      return NextResponse.redirect(new URL('/', request.url))
    }
    if (pathname.startsWith('/dashboard/verifikator') && role !== 'verifikator') {
      return NextResponse.redirect(new URL('/', request.url))
    }
  }

  return supabaseResponse
}
