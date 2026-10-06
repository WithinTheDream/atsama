'use client'

import dynamic from 'next/dynamic'

const ProjectMapDynamic = dynamic(() => import('./ProjectMap'), { ssr: false })

export default function ProjectMapClient({ projects }: { projects: any[] }) {
  return <ProjectMapDynamic projects={projects} />
}
