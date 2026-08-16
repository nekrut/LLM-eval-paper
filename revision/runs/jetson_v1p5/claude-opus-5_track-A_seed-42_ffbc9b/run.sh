#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

# 1. Reference indexing -- BWA
if [ ! -s "${REF}.bwt" ] || [ ! -s "${REF}.sa" ] || [ ! -s "${REF}.pac" ] || [ ! -s "${REF}.ann" ] || [ ! -s "${REF}.amb" ]; then
    bwa index "${REF}"
fi

# 2. Reference indexing -- samtools faidx
if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}"
fi

for sample in "${SAMPLES[@]}"; do
    r1="data/raw/${sample}_1.fq.gz"
    r2="data/raw/${sample}_2.fq.gz"
    bam="results/${sample}.bam"
    vcf="results/${sample}.vcf"
    vcfgz="results/${sample}.vcf.gz"

    # 3. Alignment + sort
    if [ ! -s "${bam}" ]; then
        bwa mem -t "${THREADS}" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "${REF}" "${r1}" "${r2}" \
        | samtools sort -@ "${THREADS}" -o "${bam}.tmp" -
        mv "${bam}.tmp" "${bam}"
    fi

    # 4. BAM index
    if [ ! -s "${bam}.bai" ]; then
        samtools index -@ "${THREADS}" "${bam}"
    fi

    # 5 + 6. Variant calling, compression, tabix index
    if [ ! -s "${vcfgz}" ]; then
        lofreq call-parallel --pp-threads "${THREADS}" -f "${REF}" -o "${vcf}" "${bam}"
        bgzip -f "${vcf}"
    fi

    if [ ! -s "${vcfgz}.tbi" ]; then
        tabix -f -p vcf "${vcfgz}"
    fi
done

# 7. Collapsed TSV
if [ ! -s results/collapsed.tsv ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv.tmp
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz" \
        | awk -v s="${sample}" 'BEGIN{OFS="\t"}{print s,$0}' >> results/collapsed.tsv.tmp
    done
    mv results/collapsed.tsv.tmp results/collapsed.tsv
fi