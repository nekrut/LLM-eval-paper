#!/usr/bin/env bash
set -euo pipefail
THREADS=4
SAMPLES=("M117-bl" "M117-ch" "M117C1-bl" "M117C1-ch")
mkdir -p results

# 1. Reference indexing — BWA
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# 2. Reference indexing — samtools faidx
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi

for sample in "${SAMPLES[@]}"; do
    # 3. Per-sample alignment + sort
    if [ ! -f "results/${sample}.bam" ] || [ "results/${sample}.bam" -ot "data/raw/${sample}_1.fq.gz" ]; then
        bwa mem -t ${THREADS} -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" data/ref/chrM.fa "data/raw/${sample}_1.fq.gz" "data/raw/${sample}_2.fq.gz" | samtools sort -@ ${THREADS} -o "results/${sample}.bam" -
    fi

    # 4. BAM index
    if [ ! -f "results/${sample}.bam.bai" ]; then
        samtools index -@ ${THREADS} "results/${sample}.bam"
    fi

    # 5. Variant calling — LoFreq
    if [ ! -f "results/${sample}.vcf" ] || [ "results/${sample}.vcf" -ot "results/${sample}.bam" ]; then
        lofreq call-parallel --pp-threads ${THREADS} -f data/ref/chrM.fa -o "results/${sample}.vcf" "results/${sample}.bam"
    fi

    # 6. VCF compression + tabix index
    if [ ! -f "results/${sample}.vcf.gz" ]; then
        bgzip -f "results/${sample}.vcf"
    fi
    if [ ! -f "results/${sample}.vcf.gz.tbi" ]; then
        tabix -p vcf "results/${sample}.vcf.gz"
    fi

    # 7. Collapsed TSV (append per sample)
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "${sample}" "$(bcftools query -f '%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n' "results/${sample}.vcf.gz")" >> results/collapsed.tsv || true
done

# Ensure header exists and is first line, then remove duplicates if any (idempotency)
if [ ! -s results/collapsed.tsv ]; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv
else
    # Reconstruct properly: keep header, then unique data lines
    head -1 results/collapsed.tsv > results/collapsed.tsv.tmp
    tail -n +2 results/collapsed.tsv | sort -u >> results/collapsed.tsv.tmp
    mv results/collapsed.tsv.tmp results/collapsed.tsv
fi

# Ensure header is present at the top (in case file was empty or only had data)
if ! head -1 results/collapsed.tsv | grep -q "^sample"; then
    printf 'sample\tchrom\tpos\tref\talt\taf\n' > results/collapsed.tsv.tmp
    cat results/collapsed.tsv >> results/collapsed.tsv.tmp
    mv results/collapsed.tsv.tmp results/collapsed.tsv
fi