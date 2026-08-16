#!/usr/bin/env bash
set -euo pipefail

THREADS=${THREADS:-4}

mkdir -p results

[[ -f data/ref/chrM.fa.bwt ]] || bwa index data/ref/chrM.fa
[[ -f data/ref/chrM.fa.fai ]] || samtools faidx data/ref/chrM.fa

for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
    if [[ ! -f "results/${sample}.bam" ]]; then
        bwa mem -t "${THREADS}" data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | \
            samtools sort -@ "${THREADS}" -o "results/${sample}.bam"
    fi

    if [[ ! -f "results/${sample}.bam.bai" ]]; then
        samtools index "results/${sample}.bam"
    fi

    if [[ ! -f "results/${sample}.vcf.gz" ]]; then
        bcftools mpileup -f data/ref/chrM.fa "results/${sample}.bam" | \
            bcftools call -cv -Oz -o "results/${sample}.vcf.gz"
    fi

    if [[ ! -f "results/${sample}.vcf.gz.tbi" ]]; then
        tabix -p vcf "results/${sample}.vcf.gz"
    fi
done

{
    printf 'sample\tchrom\tpos\tref\talt\taf\n'
    for sample in M117-bl M117-ch M117C1-bl M117C1-ch; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" | \
            awk -F'\t' -v s="${sample}" '{
                n = split($4, alts, ",")
                m = split($5, afs, ",")
                for (i = 1; i <= n; i++) {
                    af = (m >= i) ? afs[i] : "."
                    print s"\t"$1"\t"$2"\t"$3"\t"alts[i]"\t"af
                }
            }'
    done
} > results/collapsed.tsv