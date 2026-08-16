#!/usr/bin/env bash
set -euo pipefail

THREADS=4
SAMPLES=(M117-bl M117-ch M117C1-bl M117C1-ch)

mkdir -p results

# Step 2: Reference indexing (idempotent)
if [ ! -f data/ref/chrM.fa.fai ]; then
    samtools faidx data/ref/chrM.fa
fi
if [ ! -f data/ref/chrM.fa.bwt ]; then
    bwa index data/ref/chrM.fa
fi

# Step 3-5: Per-sample alignment, sorting, indexing
for sample in "${SAMPLES[@]}"; do
    bam="results/${sample}.bam"
    bai="${bam}.bai"
    
    if [ ! -f "$bai" ] || [ "data/raw/${sample}_1.fq.gz" -nt "$bam" ]; then
        bwa mem -t ${THREADS} \
            -R "@RG\tID:${sample}\tSM:${sample}\tLB:${sample}\tPL:ILLUMINA" \
            data/ref/chrM.fa \
            "data/raw/${sample}_1.fq.gz" \
            "data/raw/${sample}_2.fq.gz" \
        | samtools sort -@ ${THREADS} -o "${bam}" -
        
        samtools index -@ ${THREADS} "${bam}"
    fi
done

# Step 6-7: Per-sample variant calling, compression, indexing
for sample in "${SAMPLES[@]}"; do
    vcf="results/${sample}.vcf"
    vcfz="${vcf}.gz"
    tbi="${vcfz}.tbi"
    
    if [ ! -f "$tbi" ] || [ "results/${sample}.bam" -nt "$vcfz" ]; then
        lofreq call-parallel --pp-threads ${THREADS} --verbose \
            --ref data/ref/chrM.fa \
            --out "${vcf}" \
            results/${sample}.bam
        
        bgzip -f "${vcf}"
        tabix -p vcf "${vcfz}"
    fi
done

# Step 8: Collapse step
collapsed="results/collapsed.tsv"
need_rebuild=0

for sample in "${SAMPLES[@]}"; do
    if [ ! -f "$collapsed" ] || [ "results/${sample}.vcf.gz.tbi" -nt "$collapsed" ]; then
        need_rebuild=1
        break
    fi
done

if [ ${need_rebuild} -eq 1 ]; then
    printf "sample\tchrom\tpos\tref\talt\taf\n" > "${collapsed}"
    for sample in "${SAMPLES[@]}"; do
        bcftools query -f "${sample}\t%CHROM\t%POS\t%REF\t%ALT\t%INFO/AF\n" \
            "results/${sample}.vcf.gz" >> "${collapsed}"
    done
fi