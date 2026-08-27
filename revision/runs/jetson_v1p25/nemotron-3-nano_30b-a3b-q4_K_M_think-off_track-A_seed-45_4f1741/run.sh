#!/usr/bin/env bash
set -euo pipefail

THREADS=4
mkdir -p results

samples=(M117-bl M117-ch M117C1-bl M117C1-ch)

for sample in "${samples[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf="results/${sample}.vcf"
    vcf_gz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    if [[ -e "$tbi" && "$tbi" -nt "${vcf}.gz" ]]; then
        continue
    fi

    if [[ ! -e "$bam" || "${bam}" -ot "data/raw/${sample}_1.fq.gz" || "${bam}" -ot "data/raw/${sample}_2.fq.gz" ]]; then
        bwa mem -t 4 -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa \
            data/raw/${sample}_1.fq.gz data/raw/${sample}_2.fq.gz |
            samtools sort -@ 4 -o "$bam"
    fi

    if [[ ! -e "$bai" || "${bai}" -ot "$bam" ]]; then
        samtools index -@ 4 "$bam"
    fi

    if [[ ! -e "$vcf_gz" || "${vcf_gz}" -ot "$bam" ]]; then
        lofreq call-parallel --pp-threads 4 -f data/ref/chrM.fa -o "$vcf" "$bam"
        bgzip -c "$vcf" > "$vcf_gz"
        rm -f "$vcf"
    fi

    if [[ ! -e "$tbi" || "${tbi}" -ot "$vcf_gz" ]]; then
        tabix -p vcf "$vcf_gz"
    done

done

collapsed="results/collapsed.tsv"

if [[ ! -e "$collapsed" || "$collapsed" -nt *.vcf.gz ]]; then
    {
        printf "sample\tchrom\tpos\tref\talt\taf\n"
        for sample in "${samples[@]}"; do
            bcftools query -f 'sample=%{ID}\t%CHROM\t%POS\t%REF\t%ALT\t%AF\n' \
                --format='%{ID}\t%CHROM\t%POS\t%REF\t%ALT\t%AF' \
                results/"${sample}".vcf.gz
        done
    } | sponge "$collapsed"
fi

exit 0