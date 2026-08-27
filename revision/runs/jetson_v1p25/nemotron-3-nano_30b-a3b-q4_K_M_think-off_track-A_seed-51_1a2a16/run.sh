#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    if [[ -e "$tbi" && "$tbi" -nt "${bam}" ]]; then
        continue
    fi

    if [[ ! -e "$bai" ]]; then
        samtools index -@ 4 "$bam"
    fi

    if [[ ! -e "$vcf_gz.tbi" || "${vcf_gz}.gz" -nt "${tbi}" ]]; then
        lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o results/${sample}.vcf "$bam"
        bgzip -c "results/${sample}.vcf" > "results/${sample}.vcf.gz"
        tabix -p vcf "results/${sample}.vcf.gz"
        rm -f "results/${sample}.vcf"
    fi
done

collapsed="results/collapsed.tsv"

if [[ ! -e "$collapsed" || "$collapsed" -nt "${samples[@]/#/data/ref/chrM.fa}" ]]; then
    {
        printf 'sample\tchrom\tpos\tref\talt\taf\n'
        for sample in "${samples[@]}"; do
            bcftools query -f '{sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz"
        done
    } > "$collapsed"
fi

exit 0