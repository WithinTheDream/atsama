import { createServerSupabaseClient } from '@/lib/supabase/server'
import Link from 'next/link'
import dynamic from 'next/dynamic'
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { Progress } from '@/components/ui/progress'
import { Button } from '@/components/ui/button'
import ProjectMapClient from '@/components/map/ProjectMapClient'

export default async function ProjectsPage({
  searchParams,
}: {
  searchParams: Promise<{ category?: string }>
}) {
  const { category } = await searchParams
  const supabase = await createServerSupabaseClient()

  let query = supabase
    .from('projects')
    .select(`
      id, title, slug, summary, category, status, province, location,
      v_project_funding ( target_amount, confirmed_amount, pending_amount, remaining_target )
    `)
    .eq('status', 'aktif')

  if (category) {
    query = query.eq('category', category)
  }

  const { data: projects, error } = await query

  const categories = [
    'Konservasi & Kehutanan',
    'Pengelolaan Sampah',
    'Energi Berkelanjutan',
    'Pemberdayaan Masyarakat'
  ]

  return (
    <div className="container mx-auto p-4 space-y-6">
      <h1 className="text-3xl font-bold">Katalog Proyek Wakaf Hijau</h1>
      
      {/* Peta Interaktif */}
      <div className="w-full h-[400px] bg-slate-100 rounded-lg overflow-hidden border">
        {/* Placeholder untuk Map sampai komponen di-load */}
        <ProjectMapClient projects={projects || []} />
      </div>

      {/* Filter Kategori */}
      <div className="flex gap-2 flex-wrap">
        <Link href="/projects">
          <Badge variant={!category ? 'default' : 'outline'} className="cursor-pointer text-sm">Semua</Badge>
        </Link>
        {categories.map((c) => (
          <Link href={`/projects?category=${encodeURIComponent(c)}`} key={c}>
            <Badge variant={category === c ? 'default' : 'outline'} className="cursor-pointer text-sm">{c}</Badge>
          </Link>
        ))}
      </div>

      {/* Daftar Proyek */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {projects?.map((p: any) => {
          const funding = p.v_project_funding?.[0] || { target_amount: 0, confirmed_amount: 0 }
          const progress = funding.target_amount > 0 
            ? Math.min(100, Math.round((funding.confirmed_amount / funding.target_amount) * 100)) 
            : 0

          return (
            <Card key={p.id} className="flex flex-col">
              <CardHeader>
                <div className="flex justify-between items-start gap-2 mb-2">
                  <Badge variant="secondary">{p.category}</Badge>
                  <span className="text-xs text-muted-foreground">{p.province}</span>
                </div>
                <CardTitle className="line-clamp-2">{p.title}</CardTitle>
              </CardHeader>
              <CardContent className="flex-1 space-y-4">
                <p className="text-sm text-muted-foreground line-clamp-3">
                  {p.summary}
                </p>
                <div className="space-y-2">
                  <div className="flex justify-between text-sm">
                    <span className="font-medium">Terkumpul</span>
                    <span>{progress}%</span>
                  </div>
                  <Progress value={progress} />
                  <div className="text-xs text-muted-foreground text-right">
                    Rp {funding.confirmed_amount?.toLocaleString('id-ID')} / Rp {funding.target_amount?.toLocaleString('id-ID')}
                  </div>
                </div>
              </CardContent>
              <CardFooter>
                <Link href={`/projects/${p.slug}`} className="w-full">
                  <Button className="w-full">Lihat Detail</Button>
                </Link>
              </CardFooter>
            </Card>
          )
        })}
        {(!projects || projects.length === 0) && (
          <div className="col-span-full py-12 text-center text-muted-foreground">
            Tidak ada proyek yang ditemukan.
          </div>
        )}
      </div>
    </div>
  )
}
