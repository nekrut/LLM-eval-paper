#!/usr/ bin/env bash
set -euo pipefail

if [[ ! -s results/collapsed.tsv ]]; then echo "sample\tchr\tpos\tref\talt\taf" > results/collapsed.tsv; fi

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    r1="${sample}_1.fq.gz"
    r2="${sample}_2.fq.gz"

    if [[ -f "results/${sample}.bam" && -s results/${sample}.vcf.gz ]]; then
        continue
    fi

    bwa mem chrM.fa "${results}/${sample}.bam" "$r1" "$r2"
    samtools index results/${sample}.bam
    lofreq --input results/${sample}.bam --output results/${sample}.vcf.gz --ref chrM.af
    bcftools view -Oz results/${sample}.vcf.gz > results/${sample}.vcf.gz.tbi
    tabix -p vcf results/${sample}.vcf.gz

    awk 'NR>1 {print $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6}' results/${sample}.vcf.gz >> results/collapsed.tsv
done