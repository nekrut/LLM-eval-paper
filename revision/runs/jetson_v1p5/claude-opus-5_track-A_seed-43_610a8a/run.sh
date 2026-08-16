#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
REF="data/ref/chrM.fa"

mkdir -p results

# 1. Reference indexing -- BWA
if [ ! -s "${REF}.bwt" ] || [ ! -s "${REF}.sa" ] || [ ! -s "${REF}.ann" ] || [ ! -s "${REF}.amb" ] || [ ! -s "${REF}.pac" ]; then
    bwa index "${REF}"
fi

# 2. Reference indexing -- samtools faidx
if [ ! -s "${REF}.fai" ]; then
    samtools faidx "${REF}"
fi

for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="results/${sample}.bam.bai"
    vcf="results/${sample}.vcf"
    vcfgz="results/${sample}.vcf.gz"
    tbi="results/${sample}.vcf.gz.tbi"

    # 3. Alignment + sort
    if [ ! -s "${bam}" ]; then
        bwa mem -t "${THREADS}" \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            "${REF}" \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" \
            | samtools sort -@ "${THREADS}" -o "${bam}.tmp" -
        mv "${bam}.tmp" "${bam}"
        rm -f "${bai}"
    fi

    # 4. BAM index
    if [ ! -s "${bai}" ]; then
        samtools index -@ "${THREADS}" "${bam}"
    fi

    # 5. Variant calling -- LoFreq
    if [ ! -s "${vcfgz}" ]; then
        lofreq call-parallel --pp-threads "${THREADS}" -f "${REF}" -o "${vcf}" "${bam}"

        # 6. VCF compression + tabix index
        bgzip -f "${vcf}"
        rm -f "${tbi}"
    fi

    if [ ! -s "${tbi}" ]; then
        tabix -p vcf "${vcfgz}"
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